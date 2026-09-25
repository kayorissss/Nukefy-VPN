Drop `libbox.aar` from sing-box **1.12** here. The file is gitignored.

See `tool/build_libbox.sh`. Until the AAR is present, Android builds the `nolibbox` stub: system TUN is unavailable and the app reports that honestly instead of pretending to be connected.
