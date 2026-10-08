// No `show` list: lookupFunction/asFunction are extension methods, and a
// show clause would hide them.
import 'dart:ffi';
import 'dart:io';

/// Flips the whole Win32 process into dark app mode (undocumented
/// `uxtheme.dll` ordinal 135, available since Windows 10 1903).
///
/// This is the switch Windows itself uses to decide whether common controls
/// and `TrackPopupMenu` popups are painted dark or light. Without it the tray
/// context menu came out as a plain white window even though the app is dark.
/// The call is process-scoped and harmless on systems where the ordinal does
/// not exist: every step is guarded.
void forceDarkWin32Chrome() {
  if (!Platform.isWindows) return;
  try {
    final uxtheme = DynamicLibrary.open('uxtheme.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getProcAddress = kernel32.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>('GetProcAddress');
    // MAKEINTRESOURCE(135): when the high word is zero GetProcAddress treats
    // the pointer value as an ordinal instead of an exported name.
    final ordinal = getProcAddress(uxtheme.handle, Pointer<Void>.fromAddress(135));
    if (ordinal.address == 0) return;
    final setPreferredAppMode = Pointer<NativeFunction<Int32 Function(Int32)>>.fromAddress(ordinal.address)
        .asFunction<int Function(int)>();
    setPreferredAppMode(2); // 0 = default, 1 = allow dark, 2 = force dark
  } catch (_) {
    // Older Windows: the native menu simply keeps its default colours.
  }
}
