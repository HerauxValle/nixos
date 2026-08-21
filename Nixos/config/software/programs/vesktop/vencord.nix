# &desc: "Vencord config -- programs.vesktop.vencord.settings, plugin enable/config lives under settings.plugins."

{ config, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vesktop.vencord.settings = {
    plugins = {
      MessageLogger.enabled = true;
      ShowHiddenChannels.enabled = true;
      SpotifyControls.enabled = true;
      Translate.enabled = true;
      ViewIcons.enabled = true;
      AlwaysAnimate.enabled = true;
      BetterGifPicker.enabled = true;
      BetterSettings.enabled = true;
      CopyFileContents.enabled = true;
      FriendInvites.enabled = true;
      NoDefaultHangStatus.enabled = true;
      PermissionsViewer.enabled = true;
      PictureInPicture.enabled = true;
      RelationshipNotifier.enabled = true;
      Silent.enabled = false;
      TypingIndicator.enabled = true;
      WebRichPresence.enabled = true;
    };
  };
}
