import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import '../blur_text.dart';
import '../liquid_glass.dart';
import '../widgets/fade_in.dart';
import '../models/fan_profile.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/gemini_service.dart';

class CreatePage extends StatefulWidget {
  const CreatePage({super.key});
  @override
  State<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends State<CreatePage> {
  final _formKey       = GlobalKey<FormState>();
  final _nameCtrl      = TextEditingController();
  final _handleCtrl    = TextEditingController();
  final _cityCtrl      = TextEditingController();
  final _playerCtrl    = TextEditingController();
  final _bioCtrl       = TextEditingController();
  final _watchCtrl     = TextEditingController();
  final _moodCtrl      = TextEditingController();

  String    _selectedTeam = '';
  Uint8List? _photoBytes;
  bool _signingIn = false;
  bool _saving    = false;
  // 'auth' | 'form' | 'generating' | 'done'
  String _step = 'auth';

  static const _teams = [
    ('MI',   Color(0xFF004BA0)),
    ('CSK',  Color(0xFFFFCC00)),
    ('RCB',  Color(0xFFD4001A)),
    ('KKR',  Color(0xFF3A225D)),
    ('SRH',  Color(0xFFFF6B00)),
    ('DC',   Color(0xFF0078BC)),
    ('GT',   Color(0xFF1C4B9C)),
    ('LSG',  Color(0xFF00B4D8)),
    ('PBKS', Color(0xFFED1B24)),
    ('RR',   Color(0xFFFF69B4)),
  ];

  @override
  void initState() {
    super.initState();
    // If already signed in (e.g. returning user), skip auth step
    if (AuthService.currentUser != null) setState(() => _step = 'form');
    // Also listen for auth state changes (covers email + Google popup)
    AuthService.authStateChanges.listen((user) {
      if (user != null && mounted && _step == 'auth') {
        setState(() => _step = 'form');
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _handleCtrl.dispose(); _cityCtrl.dispose();
    _playerCtrl.dispose(); _bioCtrl.dispose();
    _watchCtrl.dispose(); _moodCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    try {
      final user = await AuthService.signInWithGoogle();
      if (!mounted) return;
      // user null = popup closed — auth state listener handles success
      if (user != null) setState(() { _step = 'form'; _signingIn = false; });
      else setState(() => _signingIn = false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _signingIn = false);
      _snack(AuthService.friendlyError(e.code));
    } catch (_) {
      if (!mounted) return;
      setState(() => _signingIn = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final xfile = await ImagePicker().pickImage(
        source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    if (mounted) setState(() => _photoBytes = bytes);
  }

  void _showPhotoPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(
                  color: kWhite.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: kGold),
            title: Text('Choose from Gallery', style: bodyStyle(size: 14)),
            onTap: () { Navigator.pop(context); _pickPhoto(ImageSource.gallery); },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: kGold),
            title: Text('Take a Photo', style: bodyStyle(size: 14)),
            onTap: () { Navigator.pop(context); _pickPhoto(ImageSource.camera); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTeam.isEmpty) { _snack('Pick your favourite team!'); return; }

    final user = AuthService.currentUser!;
    setState(() => _step = 'generating');

    String photoUrl = '';
    if (_photoBytes != null) {
      try {
        photoUrl = await FirestoreService.uploadBytes(
          path: 'photos/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          bytes: _photoBytes!,
          contentType: 'image/jpeg',
        );
      } catch (_) {}
    }

    String aiImageUrl = '';
    try {
      final imgBytes = await GeminiService.generateFanAvatar(
        name: _nameCtrl.text.trim(),
        favouriteTeam: _selectedTeam,
        favouritePlayer: _playerCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        watchStyle: _watchCtrl.text.trim(),
        matchMood: _moodCtrl.text.trim(),
      );
      if (imgBytes != null) {
        aiImageUrl = await FirestoreService.uploadBytes(
          path: 'ai_avatars/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.png',
          bytes: imgBytes,
          contentType: 'image/png',
        );
      }
    } catch (_) {}

    setState(() => _saving = true);

    try {
      final profile = FanProfile(
        id: '',
        ownerUid: user.uid,
        name: _nameCtrl.text.trim(),
        handle: _handleCtrl.text.trim().replaceAll('@', ''),
        city: _cityCtrl.text.trim(),
        favouriteTeam: _selectedTeam,
        favouritePlayer: _playerCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
        photoUrl: photoUrl,
        aiImageUrl: aiImageUrl,
        watchStyle: _watchCtrl.text.trim(),
        matchMood: _moodCtrl.text.trim(),
        createdAt: DateTime.now(),
      );
      final id = await FirestoreService.createProfile(profile);
      if (mounted) context.go('/portfolio/$id');
    } catch (e) {
      setState(() { _saving = false; _step = 'form'; });
      _snack('Something went wrong. Please try again.');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: bodyStyle(size: 13)),
          backgroundColor: kSurface, behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w > 700;
    final isGenerating = _step == 'generating' || _saving;

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          Positioned(top: -60, right: -60,
              child: _Orb(color: kGold.withOpacity(0.10), size: 340)),
          Positioned(bottom: 0, left: -80,
              child: _Orb(color: kBlue.withOpacity(0.08), size: 300)),

          if (isGenerating)
            _GeneratingOverlay(saving: _saving)
          else
            SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 64 : 20, vertical: 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: isWide ? 600 : double.infinity),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 60),
                      FadeIn(
                        child: GestureDetector(
                          onTap: () => context.go('/'),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.arrow_back_ios_new,
                                color: kGold, size: 14),
                            const SizedBox(width: 6),
                            Text('All Fans',
                                style: bodyStyle(size: 13, color: kGold)),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 28),
                      BlurText(
                        text: 'Create Your Fan Portfolio',
                        alignment: WrapAlignment.start,
                        style: headingStyle(size: isWide ? 48 : 34),
                        initialDelay: const Duration(milliseconds: 200),
                      ),
                      const SizedBox(height: 8),
                      FadeIn(
                        delay: const Duration(milliseconds: 400),
                        child: Text(
                          'Tell us about yourself — your team, your passion, your story.',
                          style: bodyStyle(size: 14,
                              color: kWhite.withOpacity(0.5)),
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (_step == 'auth')
                        _AuthStep(onSignIn: _signIn, loading: _signingIn)
                      else
                        _FormStep(
                          formKey: _formKey,
                          nameCtrl: _nameCtrl,
                          handleCtrl: _handleCtrl,
                          cityCtrl: _cityCtrl,
                          playerCtrl: _playerCtrl,
                          bioCtrl: _bioCtrl,
                          watchCtrl: _watchCtrl,
                          moodCtrl: _moodCtrl,
                          selectedTeam: _selectedTeam,
                          onTeamSelected: (t) =>
                              setState(() => _selectedTeam = t),
                          photoBytes: _photoBytes,
                          onPickPhoto: _showPhotoPicker,
                          onSubmit: _submit,
                          teams: _teams,
                        ),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            ),

          // top fade
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [kBg, kBg.withOpacity(0)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Auth step ─────────────────────────────────────────────────────────────────
class _AuthStep extends StatefulWidget {
  final VoidCallback onSignIn;
  final bool loading;
  const _AuthStep({required this.onSignIn, required this.loading});

  @override
  State<_AuthStep> createState() => _AuthStepState();
}

class _AuthStepState extends State<_AuthStep>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  final _formKey      = GlobalKey<FormState>();

  bool _obscure        = true;
  bool _emailLoading   = false;
  // 0 = sign in, 1 = register
  int  _mode           = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() => _mode = _tab.index));
  }

  @override
  void dispose() {
    _tab.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: bodyStyle(size: 13)),
          backgroundColor: kSurface, behavior: SnackBarBehavior.floating));

  Future<void> _submitEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _emailLoading = true);
    try {
      if (_mode == 0) {
        await AuthService.signInWithEmail(
            _emailCtrl.text, _passCtrl.text);
      } else {
        await AuthService.registerWithEmail(
            _emailCtrl.text, _passCtrl.text);
      }
      // auth state change will trigger parent rebuild
      widget.onSignIn();
    } on FirebaseAuthException catch (e) {
      _snack(AuthService.friendlyError(e.code));
    } catch (_) {
      _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _emailLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _snack('Enter your email above first.');
      return;
    }
    try {
      await AuthService.sendPasswordReset(email);
      _snack('Reset link sent to $email');
    } on FirebaseAuthException catch (e) {
      _snack(AuthService.friendlyError(e.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = widget.loading || _emailLoading;

    return FadeIn(
      delay: const Duration(milliseconds: 400),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(24),
        tint: kGold.withOpacity(0.04),
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          // header
          const Icon(Icons.sports_cricket, color: kGold, size: 32),
          const SizedBox(height: 12),
          Text('Join the Fan Zone',
              style: headingStyle(size: 26), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text('Sign in to build your IPL portfolio',
              style: bodyStyle(size: 13, color: kWhite.withOpacity(0.5)),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),

          // tab bar
          LiquidGlass(
            padding: const EdgeInsets.all(4),
            child: TabBar(
              controller: _tab,
              indicator: BoxDecoration(
                color: kGold.withOpacity(0.2),
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: kGold.withOpacity(0.5)),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelStyle: labelStyle(size: 13, color: kGold),
              unselectedLabelStyle:
                  bodyStyle(size: 13, color: kWhite.withOpacity(0.45)),
              tabs: const [
                Tab(text: 'Sign In'),
                Tab(text: 'Register'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // email form
          Form(
            key: _formKey,
            child: Column(children: [
              // email
              _AuthField(
                controller: _emailCtrl,
                hint: 'Email address',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 10),

              // password
              _AuthField(
                controller: _passCtrl,
                hint: 'Password',
                icon: Icons.lock_outline,
                obscure: _obscure,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined
                             : Icons.visibility_off_outlined,
                    color: kWhite.withOpacity(0.4), size: 18),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.length < 6) return 'At least 6 characters';
                  return null;
                },
              ),

              // confirm password (register only)
              if (_mode == 1) ...[
                const SizedBox(height: 10),
                _AuthField(
                  controller: _confirmCtrl,
                  hint: 'Confirm password',
                  icon: Icons.lock_outline,
                  obscure: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v != _passCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ),
              ],

              // forgot password (sign in only)
              if (_mode == 0) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _forgotPassword,
                    child: Text('Forgot password?',
                        style: bodyStyle(
                            size: 12, color: kGold.withOpacity(0.7))),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // email submit
              isLoading
                  ? const CircularProgressIndicator(color: kGold)
                  : _PillButton(
                      label: _mode == 0 ? 'Sign In' : 'Create Account',
                      icon: _mode == 0
                          ? Icons.login
                          : Icons.person_add_outlined,
                      onTap: _submitEmail,
                      color: kGold,
                    ),
            ]),
          ),

          // divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(children: [
              Expanded(child: Divider(color: kWhite.withOpacity(0.1))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or',
                    style: bodyStyle(
                        size: 12, color: kWhite.withOpacity(0.3))),
              ),
              Expanded(child: Divider(color: kWhite.withOpacity(0.1))),
            ]),
          ),

          // Google
          isLoading
              ? const SizedBox.shrink()
              : _GoogleSignInButton(onTap: widget.onSignIn),
        ]),
      ),
    );
  }
}

// ── Reusable auth text field ──────────────────────────────────────────────────
class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _AuthField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: kWhite.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kWhite.withOpacity(0.1)),
        ),
        child: TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          validator: validator,
          style: bodyStyle(size: 14),
          cursorColor: kGold,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: bodyStyle(size: 14, color: kWhite.withOpacity(0.25)),
            prefixIcon: Icon(icon, color: kWhite.withOpacity(0.3), size: 18),
            suffixIcon: suffixIcon,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            errorStyle: bodyStyle(size: 11, color: const Color(0xFFFF6B6B)),
          ),
        ),
      ),
    );
  }
}

// ── Pill button ───────────────────────────────────────────────────────────────
class _PillButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: MouseRegion(
        onEnter: (_) => _ctrl.forward(),
        onExit: (_) => _ctrl.reverse(),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) =>
                Transform.scale(scale: 1.0 + 0.02 * _ctrl.value, child: child),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9999),
                gradient: LinearGradient(
                    colors: [widget.color, widget.color.withOpacity(0.7)]),
                boxShadow: [BoxShadow(
                    color: widget.color.withOpacity(0.3),
                    blurRadius: 16, offset: const Offset(0, 4))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, color: kBg, size: 16),
                  const SizedBox(width: 8),
                  Text(widget.label, style: labelStyle(size: 14, color: kBg)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Google button ─────────────────────────────────────────────────────────────
class _GoogleSignInButton extends StatefulWidget {
  final VoidCallback onTap;
  const _GoogleSignInButton({required this.onTap});
  @override
  State<_GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<_GoogleSignInButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _ctrl.forward(),
      onExit: (_) => _ctrl.reverse(),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) =>
              Transform.scale(scale: 1.0 + 0.02 * _ctrl.value, child: child),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: kWhite,
              borderRadius: BorderRadius.circular(9999),
              boxShadow: [BoxShadow(
                  color: kWhite.withOpacity(0.12), blurRadius: 16)],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('G',
                    style: TextStyle(fontWeight: FontWeight.w700,
                        fontSize: 16, color: Color(0xFF4285F4))),
                const SizedBox(width: 10),
                Text('Continue with Google',
                    style: bodyStyle(
                        size: 14, color: kBg, weight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Form step ─────────────────────────────────────────────────────────────────
class _FormStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl, handleCtrl, cityCtrl,
      playerCtrl, bioCtrl, watchCtrl, moodCtrl;
  final String selectedTeam;
  final ValueChanged<String> onTeamSelected;
  final Uint8List? photoBytes;
  final VoidCallback onPickPhoto;
  final VoidCallback onSubmit;
  final List<(String, Color)> teams;

  const _FormStep({
    required this.formKey,
    required this.nameCtrl, required this.handleCtrl,
    required this.cityCtrl, required this.playerCtrl,
    required this.bioCtrl,  required this.watchCtrl,
    required this.moodCtrl, required this.selectedTeam,
    required this.onTeamSelected, required this.photoBytes,
    required this.onPickPhoto, required this.onSubmit,
    required this.teams,
  });

  @override
  Widget build(BuildContext context) {
    return FadeIn(
      delay: const Duration(milliseconds: 300),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel('Your Photo'),
            const SizedBox(height: 12),
            _PhotoPicker(bytes: photoBytes, onTap: onPickPhoto),
            const SizedBox(height: 28),

            const _SectionLabel('Your Identity'),
            const SizedBox(height: 12),
            _GlassField(controller: nameCtrl, label: 'Full Name',
                hint: 'e.g. Rahul Sharma', icon: Icons.person_outline,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 12),
            _GlassField(
              controller: handleCtrl, label: 'Username / Handle',
              hint: 'e.g. rahul_mi_fan', icon: Icons.alternate_email,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]'))
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (v.trim().length < 3) return 'At least 3 characters';
                return null;
              },
            ),
            const SizedBox(height: 12),
            _GlassField(controller: cityCtrl, label: 'Your City',
                hint: 'e.g. Mumbai', icon: Icons.location_on_outlined,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 28),

            const _SectionLabel('Your Cricket Soul'),
            const SizedBox(height: 12),
            Text('Favourite IPL Team',
                style: labelStyle(size: 12, color: kWhite.withOpacity(0.5))),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: teams.map((t) {
                final sel = selectedTeam == t.$1;
                return GestureDetector(
                  onTap: () => onTeamSelected(t.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9999),
                      color: sel
                          ? t.$2.withOpacity(0.25)
                          : kWhite.withOpacity(0.04),
                      border: Border.all(
                          color: sel ? t.$2 : kWhite.withOpacity(0.1),
                          width: sel ? 1.5 : 1),
                    ),
                    child: Text(t.$1,
                        style: labelStyle(size: 13,
                            color: sel ? t.$2 : kWhite.withOpacity(0.6))),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            _GlassField(controller: playerCtrl, label: 'Favourite Player',
                hint: 'e.g. Rohit Sharma', icon: Icons.sports_cricket,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 12),
            _GlassField(controller: bioCtrl, label: 'Your Fan Bio',
                hint: 'Tell the world why cricket runs through your veins...',
                icon: Icons.edit_note, maxLines: 4,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (v.trim().length < 20) return 'At least 20 characters';
                  return null;
                }),
            const SizedBox(height: 28),

            const _SectionLabel('For Your AI Avatar'),
            const SizedBox(height: 4),
            Text('These help Gemini create a personalised illustration.',
                style: bodyStyle(size: 12, color: kWhite.withOpacity(0.4))),
            const SizedBox(height: 12),
            _GlassField(controller: watchCtrl,
                label: 'How do you watch matches?',
                hint: 'e.g. With family, screaming at the TV in team jersey',
                icon: Icons.tv_outlined, maxLines: 2,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 12),
            _GlassField(controller: moodCtrl,
                label: 'Your mood when your team wins?',
                hint: 'e.g. Pure euphoria — I run around the house!',
                icon: Icons.celebration_outlined, maxLines: 2,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 36),

            SizedBox(
              width: double.infinity,
              child: _SubmitButton(onTap: onSubmit),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 3, height: 16,
            decoration: BoxDecoration(
                color: kGold, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(text, style: labelStyle(size: 13, color: kGold)),
      ]);
}

class _GlassField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;

  const _GlassField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.validator,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: labelStyle(size: 12, color: kWhite.withOpacity(0.5))),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: kWhite.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kWhite.withOpacity(0.1)),
            ),
            child: TextFormField(
              controller: controller,
              maxLines: maxLines,
              validator: validator,
              inputFormatters: inputFormatters,
              style: bodyStyle(size: 14),
              cursorColor: kGold,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: bodyStyle(size: 14, color: kWhite.withOpacity(0.25)),
                prefixIcon: Icon(icon, color: kWhite.withOpacity(0.3), size: 18),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                errorStyle: bodyStyle(size: 11, color: const Color(0xFFFF6B6B)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  final Uint8List? bytes;
  final VoidCallback onTap;
  const _PhotoPicker({required this.bytes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(20),
        tint: kGold.withOpacity(0.05),
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: kWhite.withOpacity(0.04),
              border: Border.all(color: kGold.withOpacity(0.3)),
              image: bytes != null
                  ? DecorationImage(
                      image: MemoryImage(bytes!), fit: BoxFit.cover)
                  : null,
            ),
            child: bytes == null
                ? Icon(Icons.add_a_photo_outlined,
                    color: kGold.withOpacity(0.5), size: 28)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bytes == null ? 'Add your photo' : 'Photo selected',
                    style: bodyStyle(size: 14, weight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text('Optional · tap to change',
                    style: bodyStyle(
                        size: 12, color: kWhite.withOpacity(0.4))),
              ],
            ),
          ),
          Icon(Icons.chevron_right,
              color: kWhite.withOpacity(0.3), size: 20),
        ]),
      ),
    );
  }
}

class _SubmitButton extends StatefulWidget {
  final VoidCallback onTap;
  const _SubmitButton({required this.onTap});
  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _ctrl.forward(),
      onExit: (_) => _ctrl.reverse(),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) =>
              Transform.scale(scale: 1.0 + 0.02 * _ctrl.value, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9999),
              gradient: const LinearGradient(
                  colors: [kGold, kGoldLight, kGold]),
              boxShadow: [BoxShadow(
                  color: kGold.withOpacity(0.35),
                  blurRadius: 20, offset: const Offset(0, 6))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.auto_awesome, color: kBg, size: 18),
                const SizedBox(width: 10),
                Text('Create My Portfolio',
                    style: labelStyle(size: 15, color: kBg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneratingOverlay extends StatefulWidget {
  final bool saving;
  const _GeneratingOverlay({required this.saving});
  @override
  State<_GeneratingOverlay> createState() => _GeneratingOverlayState();
}

class _GeneratingOverlayState extends State<_GeneratingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        color: kBg,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Pulsing gold orb
              Transform.scale(
                scale: 0.9 + 0.1 * _ctrl.value,
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                        color: kGold.withOpacity(0.3 + 0.2 * _ctrl.value),
                        blurRadius: 60, spreadRadius: 10)],
                    gradient: RadialGradient(colors: [
                      kGold.withOpacity(0.8),
                      kGold.withOpacity(0.2),
                    ]),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: kBg, size: 40),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                widget.saving ? 'Saving your portfolio...' : 'Generating your AI avatar...',
                style: headingStyle(size: 24),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                widget.saving
                    ? 'Almost there!'
                    : 'Gemini is painting your IPL story ✨',
                style: bodyStyle(size: 14, color: kWhite.withOpacity(0.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  final Color color;
  final double size;
  const _Orb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(
              color: color,
              blurRadius: size * 0.9,
              spreadRadius: size * 0.3)],
        ),
      );
}
