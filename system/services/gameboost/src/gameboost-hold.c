/* gameboost-hold: hold power-profiles-daemon's "performance" profile until
 * SIGTERM.
 *
 * PPD keeps a hold only while the caller stays connected to the system bus,
 * so a one-shot busctl/gdbus call would be released at once, and
 * powerprofilesctl's "launch" mode keeps a Python interpreter (~25 MB)
 * resident for the whole game. This helper idles in sigwait() instead.
 *
 * Runs as gameboost-hold.service (Type=notify): it reports READY only once
 * the hold is granted, so `systemctl start` fails when PPD is missing or
 * refuses, and start.sh then falls back to writing sysfs itself. If the
 * process dies, its bus connection closes and PPD drops the hold.
 */
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <systemd/sd-bus.h>
#include <systemd/sd-daemon.h>

#define PPD_NAME "org.freedesktop.UPower.PowerProfiles"
#define PPD_PATH "/org/freedesktop/UPower/PowerProfiles"

int main(int argc, char **argv) {
  const char *reason = argc > 1 ? argv[1] : "Game running";
  sd_bus_error err = SD_BUS_ERROR_NULL;
  sd_bus_message *reply = NULL;
  sd_bus *bus = NULL;
  uint32_t cookie;
  sigset_t ss;
  int r, sig;

  /* Block before connecting so an early SIGTERM is not lost. */
  sigemptyset(&ss);
  sigaddset(&ss, SIGTERM);
  sigaddset(&ss, SIGINT);
  sigprocmask(SIG_BLOCK, &ss, NULL);

  r = sd_bus_open_system(&bus);
  if (r < 0) {
    fprintf(stderr, "gameboost-hold: system bus: %s\n", strerror(-r));
    return 1;
  }
  sd_bus_set_method_call_timeout(bus, 2 * 1000000ULL);

  r = sd_bus_call_method(bus, PPD_NAME, PPD_PATH, PPD_NAME, "HoldProfile",
                         &err, &reply, "sss", "performance", reason,
                         "gameboost");
  if (r < 0 || sd_bus_message_read(reply, "u", &cookie) < 0) {
    fprintf(stderr, "gameboost-hold: HoldProfile failed: %s\n",
            err.message ? err.message : strerror(-r));
    sd_bus_error_free(&err);
    sd_bus_message_unref(reply);
    sd_bus_flush_close_unref(bus);
    return 1;
  }
  sd_bus_message_unref(reply);

  printf("Holding the performance profile (cookie %u)\n", cookie);
  fflush(stdout);
  sd_notify(0, "READY=1");

  sigwait(&ss, &sig);

  /* PPD may already have dropped the hold (a profile change by the user or
   * powerdevil cancels all holds); an error here is expected then. */
  sd_bus_call_method(bus, PPD_NAME, PPD_PATH, PPD_NAME, "ReleaseProfile",
                     NULL, NULL, "u", cookie);
  sd_bus_flush_close_unref(bus);
  return 0;
}
