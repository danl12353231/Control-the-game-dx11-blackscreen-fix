# Control DX11 Fog Fix

A shader patch for the expanding black rectangle in **Control Ultimate Edition** on PC. The patch covers a fault where volumetric fog can blank part of the scene while the HUD and menus stay visible.

## Compatibility

The reference installation used `Control_DX11.exe` file version `0.0.517.915`. Compatibility is determined by the exact SHA-256 hashes of `volumetriclight.obj` and `deferredlight_volume.obj`, listed in [patch-data.json](patch-data.json). The installer stops on unrecognized shader files, including other builds and conflicting shader mods. The package contains byte-level deltas and builds the replacements from your local game files.

## Install

1. Close Control.
2. Download and extract the ZIP. Do not run the installer from inside the ZIP.
3. Find `Control_DX11.exe` in the Control game folder.
4. Drag `Control_DX11.exe` onto **Control Fog Fix.bat**.
5. Launch Control in DirectX 11.

You can also drag the whole Control game folder onto the launcher. Double-click the launcher instead to install using a folder picker, check the installation, or restore the original shaders. It also finds common Steam, Epic, and GOG locations automatically. If Windows SmartScreen appears, choose **More info**, review the publisher/file details, and choose **Run anyway** only if you downloaded the files from this repository.

### PowerShell installation

Advanced users can run the script directly. Replace the example path with the folder that contains `Control_DX11.exe`.

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\ControlFogPatch.ps1 -GameFolder "D:\Games\Control"
```

PowerShell 7 users can replace `powershell.exe` with `pwsh.exe`. If the game folder requires administrator write access, run the launcher or PowerShell window as administrator.

## Unsupported shader message

The patch only changes shader files that exactly match a tested version. If the installer says a shader does not match, it safely stops without changing any files. First verify Control's files in Steam, Epic, or GOG and remove any other shader mods. If the error remains, that game build is not supported yet. Open a GitHub issue and include the shader names and SHA-256 hashes printed by the installer; do not upload copyrighted game files.

## Check or restore

Run these commands from the same folder. Close the game before restoring.

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\ControlFogPatch.ps1 -Action Status -GameFolder "D:\Games\Control"
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\ControlFogPatch.ps1 -Action Restore -GameFolder "D:\Games\Control"
```

The installer keeps each verified original beside its shader as a `.obj.pre-codex` backup. Both installation and restoration verify the expected output hashes.

## What the patch changes

- The volumetric spotlight shaders guard two scattering divisions and filter nonfinite RGB output.
- Six fog-lighting shader variants reject NaN as well as infinity before writing the fog buffers.
- The fog history pass discards invalid current values and substitutes valid current lighting for invalid history values.

The fix was tested in Direct3D 11 using a captured Central Executive frame and controlled fault injection. The original shaders let corrupted fog blank part of the scene and spread across successive frames. The patched shaders blocked the induced fault and preserved the clean replay. The precise input that starts the intermittent blackout during normal play remains unconfirmed.
