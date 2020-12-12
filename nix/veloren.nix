{
  # `crate2nix` doesn't support profiles in `Cargo.toml`, so default to release.
  # Otherwise bad performance (non-release is built with opt level 0)
  release ? true
, cratesToBuild ? [ "veloren-voxygen" "veloren-server-cli" ]
, disableGitLfsCheck ? false
, nixpkgs
, sources
, system
, sourceInfo ? { }
}:
let
  common = import ./common.nix {
    inherit
      nixpkgs
      sources
      system
      ;
  };
  inherit (common) pkgs;
  utils = import ./utils.nix { inherit pkgs; };

  meta = with pkgs.stdenv.lib; {
    description = "Veloren is a multiplayer voxel RPG written in Rust.";
    longDescription = ''
      Veloren is a multiplayer voxel RPG written in Rust.
      It is inspired by games such as Cube World, Legend of Zelda: Breath of the Wild, Dwarf Fortress and Minecraft.
    '';
    homepage = "https://veloren.net";
    upstream = "https://gitlab.com/veloren/veloren";
    license = licenses.gpl3;
    maintainers = [ maintainers.yusdacra ];
    # TODO: Make this work on BSD and Mac OS
    platforms = platforms.linux;
  };

  prettyRev = with sourceInfo;
    if sourceInfo ? rev && sourceInfo ? lastModified
    then builtins.substring 0 8 rev + "/" + utils.dateTimeFormat lastModified
    else (utils.getGitInfo ../.git).gitHash;
  # If gitTag has a tag (meaning the commit we are on is a *release*), use
  # it as version, else: just use the prettified hash we have, if we don't
  # have it the build fails.
  # Must be in format f4987672/2020-12-10-12:00
  version =
    if sourceInfo ? tag then sourceInfo.tag
    else if prettyRev != "" then prettyRev
    else throw "Need a tag or at least revision + lastModified in order to determine version";
  # Sanitize version string since it might contain illegal characters for a Nix store path
  # Used in the derivation(s) name
  sanitizedVersion = pkgs.stdenv.lib.strings.sanitizeDerivationName version;

  veloren-assets = pkgs.runCommand "makeAssetsDir" { } ''
    mkdir $out
    ln -sf ${../assets} $out/assets
  '';

  velorenVoxygenDesktopFile = pkgs.makeDesktopItem rec {
    name = "veloren-voxygen";
    exec = name;
    icon = ../assets/voxygen/logo.ico;
    comment =
      "Official client for Veloren - the open-world, open-source multiplayer voxel RPG";
    desktopName = "Voxygen";
    genericName = "Veloren Client";
    categories = "Game;";
  };

  veloren-crates = with pkgs;
    callPackage ./Cargo.nix {
      defaultCrateOverrides = with common;
        defaultCrateOverrides // {
          libudev-sys = _: crateDeps.libudev-sys;
          alsa-sys = _: crateDeps.alsa-sys;
          veloren-network = _: crateDeps.veloren-network;
          veloren-common = _: {
            # Disable `git-lfs` check here since we check it ourselves
            # We have to include the command output here, otherwise Nix won't run it
            DISABLE_GIT_LFS_CHECK = utils.isGitLfsSetup common.gitLfsCheckFile;
            # Declare env values here so that `common/build.rs` sees them
            NIX_GIT_HASH = prettyRev;
            # if we have a tag (meaning the commit we are on is a *release*),
            # use it as version, else use the prettified hash we have;
            # if we don't have it the build fails
            NIX_GIT_TAG = version;
          };
          veloren-server-cli = _: {
            name = "veloren-server-cli_${sanitizedVersion}";
            inherit version;
            VELOREN_USERDATA_STRATEGY = "system";
            nativeBuildInputs = [ makeWrapper ];
            postInstall = ''
              wrapProgram $out/bin/veloren-server-cli --set VELOREN_ASSETS ${veloren-assets}
            '';
            meta = meta // {
              longDescription = ''
                ${meta.longDescription}
                "This package includes the server CLI."
              '';
            };
          };
          veloren-voxygen = _: {
            name = "veloren-voxygen_${sanitizedVersion}";
            inherit version;
            VELOREN_USERDATA_STRATEGY = "system";
            inherit (crateDeps.veloren-voxygen) buildInputs;
            nativeBuildInputs = crateDeps.veloren-voxygen.nativeBuildInputs
            ++ [ makeWrapper copyDesktopItems ];
            desktopItems = [ velorenVoxygenDesktopFile ];
            postInstall = ''
              wrapProgram $out/bin/veloren-voxygen\
                --set VELOREN_ASSETS ${veloren-assets}\
                --set LD_LIBRARY_PATH ${
                  lib.makeLibraryPath common.voxygenNeededLibs
                }
            '';
            meta = meta // {
              longDescription = ''
                ${meta.longDescription}
                "This package includes the official client, Voxygen."
              '';
            };
          };
        };
      inherit release pkgs;
    };

  makePkg = name: veloren-crates.workspaceMembers."${name}".build;
in
(pkgs.lib.genAttrs cratesToBuild makePkg)