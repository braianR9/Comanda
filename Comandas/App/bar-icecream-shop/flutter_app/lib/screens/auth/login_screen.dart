import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    await auth.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    if (auth.status == AuthStatus.authenticated) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 800;
    return Scaffold(
      body: Stack(
        children: [
          const _AnimatedBackground(),
          SafeArea(
            child: isWide ? _buildWideLayout() : _buildNarrowLayout(),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        Expanded(flex: 5, child: _buildBrandSide()),
        Expanded(
          flex: 4,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: _buildGlassCard(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Column(
                children: [
                  _buildCompactLogo(),
                  const SizedBox(height: 32),
                  _buildGlassCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandSide() {
    return Container(
      color: const Color(0xFF6C5CE7),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FocoLogo(size: 80),
            const SizedBox(height: 20),
            Text(
              'FOCO',
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Tu negocio\nen nuestras manos.',
              style: GoogleFonts.poppins(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Gestioná ventas, stock y tu negocio\ndesde cualquier lugar.',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.white.withOpacity(0.6),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 48),
            const Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _FeatureChip(
                    icon: Icons.point_of_sale_rounded, label: 'Ventas'),
                _FeatureChip(icon: Icons.inventory_2_rounded, label: 'Stock'),
                _FeatureChip(
                    icon: Icons.account_balance_wallet_rounded, label: 'Caja'),
                _FeatureChip(
                    icon: Icons.bar_chart_rounded, label: 'Estadísticas'),
                _FeatureChip(icon: Icons.people_rounded, label: 'Clientes'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactLogo() {
    return Column(
      children: [
        const FocoLogo(size: 72),
        const SizedBox(height: 14),
        Text(
          'FOCO',
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2D2260),
            letterSpacing: 3,
          ),
        ),
        Text(
          'Gestioná tu negocio',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: const Color(0xFF6B6589),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E1EE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(36),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Iniciá sesión',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2D2260),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Accedé al panel de tu negocio',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF6B6589),
                ),
              ),
              const SizedBox(height: 32),
              _GlassField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onChanged: (_) => context.read<AuthProvider>().clearError(),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Ingresá tu email';
                  }
                  if (!v.contains('@')) {
                    return 'Email inválido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              _GlassField(
                controller: _passwordController,
                label: 'Contraseña',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _handleLogin(),
                onChanged: (_) => context.read<AuthProvider>().clearError(),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Ingresá tu contraseña';
                  }
                  if (v.length < 6) {
                    return 'Mínimo 6 caracteres';
                  }
                  return null;
                },
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: const Color(0xFF6B6589),
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  ),
                  child: Text(
                    '¿Olvidaste tu contraseña?',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF6C5CE7),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Consumer<AuthProvider>(
                builder: (_, auth, __) {
                  if (auth.errorMessage == null) {
                    return const SizedBox.shrink();
                  }
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppColors.error.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            auth.errorMessage!,
                            style: GoogleFonts.poppins(
                              color: AppColors.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Consumer<AuthProvider>(
                builder: (_, auth, __) {
                  return _GradientButton(
                    onPressed: auth.isLoading ? null : _handleLogin,
                    isLoading: auth.isLoading,
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// Fondo compartido con el resto de la aplicación.
class _AnimatedBackground extends StatelessWidget {
  const _AnimatedBackground();

  @override
  Widget build(BuildContext context) {
    return Container(color: const Color(0xFFF5F5F8));
  }
}

// Chips de características
class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(50),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFFFF8C42), size: 15),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Campo de texto glass
class _GlassField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onFieldSubmitted;
  final Widget? suffixIcon;

  const _GlassField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      style: GoogleFonts.poppins(color: const Color(0xFF2D2260), fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(
          color: const Color(0xFF6B6589),
          fontSize: 14,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF9E8FCC), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF8F7FC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE4E1EE)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE4E1EE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF6C5CE7), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.error.withOpacity(0.7)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        errorStyle: GoogleFonts.poppins(
            color: AppColors.error.withOpacity(0.9), fontSize: 12),
      ),
    );
  }
}

// Botón con gradiente
class _GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  const _GradientButton({required this.onPressed, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: onPressed == null
              ? const LinearGradient(
                  colors: [Color(0xFFD8D5E3), Color(0xFFC5C1D4)])
              : const LinearGradient(
                  colors: [Color(0xFF6C5CE7), Color(0xFF8777E8)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: onPressed == null
              ? []
              : [
                  BoxShadow(
                    color: const Color(0xFF6C5CE7).withOpacity(0.28),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'Ingresar al panel',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}

// FocoLogo: punto central + cuatro esquinas
class FocoLogo extends StatefulWidget {
  final double size;
  final Color color;
  const FocoLogo({super.key, required this.size, this.color = Colors.white});

  @override
  State<FocoLogo> createState() => _FocoLogoState();
}

class _FocoLogoState extends State<FocoLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _focusController;
  late final Animation<double> _focusScale;

  @override
  void initState() {
    super.initState();
    _focusController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _focusScale = Tween<double>(begin: 1, end: 1.1).animate(
      CurvedAnimation(parent: _focusController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _focusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _focusScale,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(painter: _FocoPainter(color: widget.color)),
      ),
    );
  }
}

class _FocoPainter extends CustomPainter {
  final Color color;
  const _FocoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final arm = w * 0.28;
    final gap = w * 0.08;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawLine(Offset(gap, gap + arm), Offset(gap, gap), stroke);
    canvas.drawLine(Offset(gap, gap), Offset(gap + arm, gap), stroke);
    canvas.drawLine(Offset(w - gap - arm, gap), Offset(w - gap, gap), stroke);
    canvas.drawLine(Offset(w - gap, gap), Offset(w - gap, gap + arm), stroke);
    canvas.drawLine(Offset(gap, h - gap - arm), Offset(gap, h - gap), stroke);
    canvas.drawLine(Offset(gap, h - gap), Offset(gap + arm, h - gap), stroke);
    canvas.drawLine(
        Offset(w - gap - arm, h - gap), Offset(w - gap, h - gap), stroke);
    canvas.drawLine(
        Offset(w - gap, h - gap), Offset(w - gap, h - gap - arm), stroke);
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.1, dot);
  }

  @override
  bool shouldRepaint(_FocoPainter old) => old.color != color;
}
