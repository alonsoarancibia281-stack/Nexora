class Validators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _password = RegExp(
    r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$',
  );

  static String? email(String? value) =>
      value == null || !_email.hasMatch(value.trim()) ? 'Correo inválido' : null;

  static String? password(String? value) =>
      value == null || !_password.hasMatch(value)
          ? 'Usa 8+ caracteres, mayúscula, minúscula, número y símbolo'
          : null;

  static String? required(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obligatorio' : null;
}
