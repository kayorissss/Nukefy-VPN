# Windows release security and antivirus detections

Nukefy VPN is a networking tool. The Windows bundle contains the official
Flowseal `zapret` files and `winws.exe`, which uses WinDivert to inspect and
redirect packets. A security product can therefore label the installer as a
risk tool or PUA even when the file has not been modified by Nukefy. That
label describes sensitive networking behaviour; it is not a claim that every
alert is a false positive. Each vendor result must still be reviewed.

The release pipeline does not rename binaries to evade detection, disable
Windows Defender, or add an antivirus exclusion. It also does not pack the
optional Flowseal TG WS Proxy executable into the Nukefy installer. That
component is downloaded only after an explicit action in Settings and is
accepted only when the SHA-256 digest returned by the official GitHub release
API matches.

## What to verify

1. Download release files from the repository's GitHub release page.
2. Download `SHA256SUMS.txt` from the same release and compare it with a local
   SHA-256 calculation (`Get-FileHash` on Windows).
3. Keep Microsoft Defender and the installed security product enabled. Do not
   run a file whose hash differs from the release manifest.
4. If a vendor still blocks a matching file, submit that exact hash and the
   official release URL to the vendor for review. The installer can contain
   `winws.exe` and WinDivert precisely because ZAPRET cannot work without its
   packet-filtering mechanism.

The installer uses a non-solid ZIP payload rather than a high-compression
single block so scanners can inspect its contents more easily. Optional
Authenticode signing is enabled in CI when the repository owner provides a
certificate through GitHub Actions secrets; no private key is stored in this
repository.
