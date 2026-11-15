import 'package:flutter/material.dart';

/// Colores de Odai: el morado de las maquetas y sus tonos, con el azul del logo como segundo color.
const moradoCabecera = Color(0xFF8569BE);
/// Botones y acentos: un tono más fuerte que la cabecera para que el texto blanco se lea con sol.
const moradoOdai = Color(0xFF6A4BA8);
const moradoOscuro = Color(0xFF45306F);
/// Marcos de tarjetas, buscador y filtros.
const bordeMorado = Color(0xFF8E7BC6);
/// Relleno suave: filtro elegido, unidades y botón de agregar.
const lavanda = Color(0xFFE3DAF5);
/// Fondo de las pantallas.
const fondoOdai = Color(0xFFF7F5FA);
const azulOdai = Color(0xFF2F8FE0);
const verdeOdai = Color(0xFF43A047);
/// Compatibilidad: algunos marcos usan el gris oscuro.
const bordeOdai = Color(0xFF616161);
const azulMarino = moradoOscuro;
const radioMarco = 8.0;

ThemeData temaOdai(Brightness brillo) {
  final colores = ColorScheme.fromSeed(
    seedColor: moradoOdai,
    brightness: Brightness.light,
    primary: moradoOdai,
    onPrimary: Colors.white,
    primaryContainer: lavanda,
    onPrimaryContainer: moradoOscuro,
    secondary: moradoCabecera,
    secondaryContainer: lavanda,
    tertiary: azulOdai,
    surface: fondoOdai,
    outline: bordeMorado,
  );
  final marco = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radioMarco), borderSide: const BorderSide(color: bordeMorado, width: 1.2));
  final rectangulo = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioMarco));
  return ThemeData(
    colorScheme: colores,
    useMaterial3: true,
    scaffoldBackgroundColor: fondoOdai,
    appBarTheme: const AppBarTheme(
      backgroundColor: moradoCabecera,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), side: const BorderSide(color: bordeMorado, width: 1.2)),
    ),
    // Letras y bordes más marcados para leer bien en la calle.
    textTheme: ThemeData(brightness: Brightness.light).textTheme.apply(
          bodyColor: const Color(0xFF111111),
          displayColor: const Color(0xFF111111),
        ),
    dividerTheme: const DividerThemeData(color: bordeMorado),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: marco,
      enabledBorder: marco,
      focusedBorder: marco.copyWith(borderSide: const BorderSide(color: moradoOdai, width: 2)),
      labelStyle: const TextStyle(color: Color(0xFF333333)),
    ),
    // Todos los botones rectangulares, con el mismo marco que el buscador.
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            backgroundColor: moradoOdai, foregroundColor: Colors.white, shape: rectangulo,
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(shape: rectangulo)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: moradoOscuro, shape: rectangulo)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: rectangulo)),
    segmentedButtonTheme: SegmentedButtonThemeData(style: SegmentedButton.styleFrom(shape: rectangulo)),
    chipTheme: ChipThemeData(shape: rectangulo),
    floatingActionButtonTheme: FloatingActionButtonThemeData(shape: rectangulo),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: moradoOdai, linearTrackColor: lavanda),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: moradoOscuro,
        side: const BorderSide(color: bordeMorado, width: 1.2),
        shape: rectangulo,
      ),
    ),
  );
}
