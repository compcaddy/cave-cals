# Local folder rename

The repository now lives at `/Users/phil/Documents/GIT/CaveCals`. Git history and uncommitted files were preserved. The Xcode project uses relative source references, and XcodeBuildMCP now targets the new path. The local web server was restarted from this folder and returned HTTP 200. A simulator build from the renamed project succeeded.

`/Users/phil/Documents/GIT/ECC2` is a compatibility symlink to the new folder, not a second checkout. Keep it while existing Codex tasks still use that working directory.

Codex’s trusted-project configuration uses the new path. Its running desktop project registry still uses the old project entry: it overwrote an attempted on-disk update. Open/add the new CaveCals folder in Codex and move future work there before removing the compatibility symlink. Codex blocks computer-use control of its own UI and exposes no project-relocation tool in this session, so that UI update remains manual.
