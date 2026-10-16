{ gitUsername, gitEmail, ... }:

{
  programs.git = {
    enable = true;

    settings = {
      user.name = gitUsername;
      user.email = gitEmail;

      # Default branch
      init.defaultBranch = "main";

      # Push behavior
      push.default = "upstream";
      remote.pushDefault = "upstream";
      push.autoSetupRemote = true;
    };
  };
}
