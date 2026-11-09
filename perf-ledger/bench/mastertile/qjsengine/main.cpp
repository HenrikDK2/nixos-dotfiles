#include <QCoreApplication>
#include <QJSEngine>
#include <QElapsedTimer>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include "win.h"
// usage: bench <old|new> <scenario> <N> [rounds]
int main(int argc, char** argv){
    QCoreApplication app(argc, argv);
    const bool isNew = !strcmp(argv[1],"new");
    const char* sc = argv[2]; long N = atol(argv[3]);
    int rounds = argc>4 ? atoi(argv[4]) : 0;
    QJSEngine eng; eng.installExtensions(QJSEngine::ConsoleExtension);
    Win w; Tile tile;
    eng.globalObject().setProperty("win", eng.newQObject(&w));
    eng.globalObject().setProperty("theTile", eng.newQObject(&tile));
    QJSEngine::setObjectOwnership(&w, QJSEngine::CppOwnership);
    QJSEngine::setObjectOwnership(&tile, QJSEngine::CppOwnership);
    QString guardOld = "window.fullScreen || window.minimized || window.move || window.resize || window.tile || state.userUntiled";
    QString guardNew = "state.userUntiled || window.tile || window.fullScreen || window.move || window.resize || window.minimized";
    QString src = QString(
      "var hits=0; function rootTileFor(w){ return null; }\n"
      "function track(window){ const state = window.mt = {tile:null,key:null,userUntiled:false};\n"
      "  window.frameGeometryChanged.connect(() => {\n"
      "    if (%1) { return; }\n"
      "    hits++; const root = rootTileFor(window); if (!root) return;\n"
      "  });\n"
      "  return state; }\n"
      "var st = track(win);\n").arg(isNew?guardNew:guardOld);
    QJSValue r = eng.evaluate(src);
    if (r.isError()) { fprintf(stderr, "%s\n", qPrintable(r.toString())); return 1; }
    QJSValue st = eng.globalObject().property("st");
    // scenarios
    if (!strcmp(sc,"tiled")) { w.t=&tile; }
    else if (!strcmp(sc,"drag")) { w.mv=true; st.setProperty("userUntiled", true); }
    else if (!strcmp(sc,"resize")) { w.rs=true; st.setProperty("userUntiled", true); }
    else if (!strcmp(sc,"dropped")) { st.setProperty("userUntiled", true); }
    else if (!strcmp(sc,"float")) { }
    else if (!strcmp(sc,"fs_notile")) { w.fs=true; }
    else if (!strcmp(sc,"fs_tile")) { w.fs=true; w.t=&tile; }
    else if (!strcmp(sc,"minimized")) { w.mini=true; }
    else { fprintf(stderr,"bad scen\n"); return 2; }
    for (int i=0;i<2000;i++) w.fire(); // warmup (also lets QV4 JIT kick in when enabled)
    if (rounds==0) { for (long i=0;i<N;i++) w.fire(); }
    else {
      for (int k=0;k<rounds;k++){ QElapsedTimer t; t.start(); for (long i=0;i<N;i++) w.fire(); printf("%.2f\n", t.nsecsElapsed()/(double)N); }
    }
    fprintf(stderr, "hits=%d\n", eng.globalObject().property("hits").toInt());
    return 0;
}
