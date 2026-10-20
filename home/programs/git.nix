{ gitUsername, gitEmail, ... }:

{
  programs.git = {
    enable = true;

    settings = {
      user.name = gitUsername;
      user.email = gitEmail;

      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = true;
    };
  };
}
