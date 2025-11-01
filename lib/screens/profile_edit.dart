import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';

enum _UsernameStatus { idle, checking, available, taken, invalid }

const Map<String, String> _profileEditStrings = {
  'profile_edit_title': 'تعديل الملف الشخصي',
  'change_cover': 'تغيير الغلاف',
  'change_photo': 'تغيير الصورة',
  'display_name': 'الاسم المعروض',
  'username': 'اسم المستخدم',
  'bio': 'النبذة',
  'website': 'الموقع / الرابط',
  'location': 'الموقع الجغرافي',
  'birthday': 'تاريخ الميلاد',
  'privacy_title': 'إعدادات الخصوصية',
  'privacy_show_email': 'إظهار بريدي الإلكتروني',
  'privacy_dm_anyone': 'أي شخص يمكنه مراسلتي',
  'privacy_dm_followers': 'المتابعون فقط يمكنهم مراسلتي',
  'save': 'حفظ',
  'cancel': 'إلغاء',
  'discard_changes_title': 'تجاهل التغييرات؟',
  'discard_changes_message': 'لديك تغييرات غير محفوظة. هل تريد الخروج بدون حفظ؟',
  'stay': 'البقاء',
  'discard': 'تجاهل',
  'unsaved_changes': 'غير محفوظ',
  'saved_success': 'تم تحديث الملف الشخصي بنجاح',
  'username_taken': 'اسم المستخدم محجوز',
  'username_ok': 'اسم المستخدم متاح ✅',
  'invalid_website': 'يرجى إدخال رابط http أو https صالح',
  'username_required': 'اسم المستخدم مطلوب',
  'username_invalid': 'استخدم أحرفًا صغيرة أو أرقامًا أو شرطة سفلية (3-20).',
  'display_name_required': 'الاسم مطلوب',
  'display_name_too_long': 'الاسم يجب ألا يتجاوز 40 حرفًا',
  'bio_limit': 'النبذة لا يجب أن تتجاوز 160 حرفًا',
  'choose_source': 'اختر مصدر الصورة',
  'camera': 'الكاميرا',
  'gallery': 'المعرض',
  'clear_birthday': 'إزالة التاريخ',
  'pick_birthday': 'اختيار تاريخ',
  'unexpected_error': 'حدث خطأ غير متوقع. حاول لاحقًا.',
  'upload_failed': 'تعذر رفع الصورة. حاول مجددًا.',
  'login_required': 'يرجى تسجيل الدخول لتعديل ملفك الشخصي.',
  'status': 'الحالة',
  'verified': 'موثّق',
  'vip': 'العضوية',
  'vip_none': 'بدون',
  'coins': 'العملات',
  'expires': 'ينتهي',
  'request_verification': 'طلب التحقق',
  'verification_requested': 'تم إرسال طلب التحقق',
  'request_verification_failed': 'تعذر إرسال الطلب. حاول لاحقًا.',
};

String _t(String key) => _profileEditStrings[key] ?? key;

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  final _picker = ImagePicker();
  final _userService = UserService();
  final _storageService = StorageService();

  final ValueNotifier<bool> _isDirty = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isSaving = ValueNotifier<bool>(false);

  Uint8List? _avatarPreview;
  Uint8List? _coverPreview;
  XFile? _avatarFile;
  XFile? _coverFile;

  bool _loading = true;
  bool _checkingUsername = false;
  bool _verified = false;
  VipStatus _vipStatus = const VipStatus(tier: 'none');
  int _coins = 0;
  bool _verificationRequested = false;
  bool _requestingVerification = false;

  String? _uid;
  String? _initialUsername;
  String? _usernameErrorKey;
  String? _websiteErrorKey;
  String? _loadError;

  _UsernameStatus _usernameStatus = _UsernameStatus.idle;
  DateTime? _birthdate;
  bool _showEmail = false;
  String _dmPermission = 'all';
  DateTime? _vipExpiry;

  String? _currentPhotoUrl;
  String? _currentCoverUrl;

  String _initialDisplayName = '';
  String? _initialBio;
  String? _initialWebsite;
  String? _initialLocation;
  DateTime? _initialBirthdate;
  bool _initialShowEmail = false;
  String _initialDmPermission = 'all';

  Timer? _usernameDebounce;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _websiteCtrl.dispose();
    _locationCtrl.dispose();
    _usernameDebounce?.cancel();
    _isDirty.dispose();
    _isSaving.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = AuthService.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _loadError = 'no-auth';
      });
      return;
    }
    _uid = user.uid;
    try {
      final profile = await _userService.getCurrentProfile(user.uid);
      _displayNameCtrl.text = profile.displayName.isNotEmpty
          ? profile.displayName
          : (user.displayName ?? '');
      final username = profile.username.toLowerCase();
      _usernameCtrl.text = username;
      _initialUsername = username;
      _usernameStatus = username.isNotEmpty
          ? _UsernameStatus.available
          : _UsernameStatus.idle;
      _bioCtrl.text = profile.bio ?? '';
      _websiteCtrl.text = profile.website ?? '';
      _locationCtrl.text = profile.location ?? '';
      _birthdate = profile.birthdate;
      _showEmail = profile.showEmail;
      _dmPermission = profile.dmPermission;
      _currentPhotoUrl = profile.photoURL ?? user.photoURL;
      _currentCoverUrl = profile.coverURL;
      _verified = profile.verified;
      _vipStatus = profile.vip;
      _vipExpiry = profile.vip.expiresAt;
      _coins = profile.coins;
      final requestDoc = await cf.FirebaseFirestore.instance
          .collection('verification_requests')
          .doc(user.uid)
          .get();
      _verificationRequested = requestDoc.exists;

      _initialDisplayName = _displayNameCtrl.text.trim();
      _initialBio = _bioCtrl.text.trim().isNotEmpty ? _bioCtrl.text.trim() : null;
      _initialWebsite = _websiteCtrl.text.trim().isNotEmpty ? _websiteCtrl.text.trim() : null;
      _initialLocation = _locationCtrl.text.trim().isNotEmpty ? _locationCtrl.text.trim() : null;
      _initialBirthdate = _birthdate;
      _initialShowEmail = _showEmail;
      _initialDmPermission = _dmPermission;
      _isDirty.value = false;
    } catch (err) {
      _loadError = err.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _setUsernameStatus(_UsernameStatus status, {String? errorKey}) {
    _usernameDebounce?.cancel();
    setState(() {
      _usernameStatus = status;
      _usernameErrorKey = errorKey;
      _checkingUsername = status == _UsernameStatus.checking;
    });
    if (_formKey.currentState != null) {
      _formKey.currentState!.validate();
    }
    _updateDirtyState();
  }

  void _updateDirtyState() {
    final displayName = _displayNameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    final website = _websiteCtrl.text.trim();
    final location = _locationCtrl.text.trim();

    final normalizedBio = bio.isEmpty ? null : bio;
    final normalizedWebsite = website.isEmpty ? null : website;
    final normalizedLocation = location.isEmpty ? null : location;

    final dirty =
        displayName != _initialDisplayName ||
        username != (_initialUsername ?? '') ||
        normalizedBio != _initialBio ||
        normalizedWebsite != _initialWebsite ||
        normalizedLocation != _initialLocation ||
        _birthdate != _initialBirthdate ||
        _showEmail != _initialShowEmail ||
        _dmPermission != _initialDmPermission ||
        _avatarFile != null ||
        _coverFile != null;

    if (_isDirty.value != dirty) {
      _isDirty.value = dirty;
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _onUsernameChanged(String value) {
    final trimmed = value.trim();
    if (_uid == null) return;
    _usernameDebounce?.cancel();

    if (trimmed.isEmpty) {
      _setUsernameStatus(_UsernameStatus.invalid, errorKey: 'username_required');
      return;
    }

    final validationError = UserProfile.validateUsername(trimmed);
    if (validationError != null) {
      _setUsernameStatus(_UsernameStatus.invalid, errorKey: validationError);
      return;
    }

    if (_initialUsername != null && trimmed == _initialUsername) {
      _setUsernameStatus(
        trimmed.isEmpty ? _UsernameStatus.idle : _UsernameStatus.available,
      );
      return;
    }

    _setUsernameStatus(_UsernameStatus.checking);
    _usernameDebounce = Timer(const Duration(milliseconds: 420), () async {
      try {
        final available = await _userService.isUsernameAvailable(
          trimmed,
          excludeUid: _uid,
        );
        if (!mounted) return;
        if (available) {
          _setUsernameStatus(_UsernameStatus.available);
        } else {
          _setUsernameStatus(_UsernameStatus.taken, errorKey: 'username_taken');
        }
      } catch (err) {
        if (!mounted) return;
        _setUsernameStatus(_UsernameStatus.invalid, errorKey: err.toString());
      }
    });
    _updateDirtyState();
  }

  bool get _isSaveEnabled {
    if (_loading || _isSaving.value || _checkingUsername) return false;
    if (!_isDirty.value) return false;
    final name = _displayNameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    if (name.isEmpty || name.length > 40) return false;
    if (username.isEmpty) return false;
    if (_usernameStatus == _UsernameStatus.invalid ||
        _usernameStatus == _UsernameStatus.taken) {
      return false;
    }
    if (_bioCtrl.text.trim().length > 160) return false;
    if (_websiteErrorKey != null) return false;
    return true;
  }

  String _formatVipTierLabel(String tier) {
    final normalised = tier.trim().toLowerCase();
    if (normalised.isEmpty || normalised == 'none') {
      return _t('vip_none');
    }
    return normalised[0].toUpperCase() + normalised.substring(1);
  }

  String _formatCoins(int coins) {
    final formatter = NumberFormat.decimalPattern();
    return formatter.format(coins);
  }

  Widget _buildStatusRow({
    required String label,
    required Widget value,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          value,
        ],
      ),
    );
  }

  Widget _buildAccountStatusSection(ThemeData theme) {
    final vipLabel = _formatVipTierLabel(_vipStatus.tier);
    final expiry = _vipExpiry;
    final expiresText = expiry != null
        ? '${_t('expires')}: ${DateFormat('dd MMM yyyy').format(expiry)}'
        : null;

    final surface = theme.colorScheme.surface;
    final shadowColor = theme.colorScheme.shadow.withOpacity(0.1);

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _t('status'),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            textDirection: Directionality.of(context),
          ),
          const SizedBox(height: 12),
          _buildStatusRow(
            label: _t('verified'),
            value: Text(_verified ? '✅' : '❌'),
          ),
          _buildStatusRow(
            label: _t('vip'),
            value: Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(vipLabel),
                  if (expiresText != null)
                    Text(
                      expiresText,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                ],
              ),
            ),
          ),
          _buildStatusRow(
            label: _t('coins'),
            value: Text(_formatCoins(_coins)),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonal(
              onPressed: _verificationRequested || _requestingVerification
                  ? null
                  : _requestVerification,
              child: _requestingVerification
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_t('request_verification')),
            ),
          ),
          if (_verificationRequested) ...[
            const SizedBox(height: 8),
            Text(
              _t('verification_requested'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
              textAlign: TextAlign.start,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _requestVerification() async {
    final uid = _uid;
    if (uid == null || _verificationRequested) {
      return;
    }
    setState(() {
      _requestingVerification = true;
    });
    try {
      final ref =
          cf.FirebaseFirestore.instance.collection('verification_requests').doc(uid);
      await ref.set({
        'uid': uid,
        'createdAt': cf.FieldValue.serverTimestamp(),
        'displayName': _displayNameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _verificationRequested = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('verification_requested'))),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('request_verification_failed'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _requestingVerification = false;
        });
      }
    }
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _t('choose_source'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded),
                  title: Text(_t('camera')),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: Text(_t('gallery')),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (source == null) return;
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _avatarFile = picked;
        _avatarPreview = bytes;
      });
      _updateDirtyState();
    } on PlatformException catch (err) {
      _showSnack(_t('unexpected_error') + '\n${err.message ?? err.code}');
    }
  }

  Future<void> _pickCover() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _coverFile = picked;
        _coverPreview = bytes;
      });
      _updateDirtyState();
    } on PlatformException catch (err) {
      _showSnack(_t('unexpected_error') + '\n${err.message ?? err.code}');
    }
  }

  Future<void> _pickBirthdate() async {
    final initial = _birthdate ?? DateTime(DateTime.now().year - 18, 1, 1);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: now,
      initialDate: initial.isAfter(now) ? now : initial,
      textDirection: ui.TextDirection.rtl,
    );
    if (picked != null) {
      setState(() => _birthdate = picked);
      _updateDirtyState();
    }
  }

  String? _formatBirthdate(DateTime? value) {
    if (value == null) return null;
    try {
      return DateFormat.yMMMMd('ar').format(value);
    } catch (_) {
      return DateFormat.yMd().format(value);
    }
  }

  String? _validateWebsite(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return 'invalid_website';
    }
    final hasValidScheme = uri.scheme == 'http' || uri.scheme == 'https';
    if (!hasValidScheme || (uri.host.isEmpty && uri.authority.isEmpty)) {
      return 'invalid_website';
    }
    return null;
  }

  Future<void> _handleSave() async {
    if (!_isSaveEnabled) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    final user = AuthService.currentUser;
    if (user == null) return;

    FocusScope.of(context).unfocus();

    final websiteError = _validateWebsite(_websiteCtrl.text);
    if (websiteError != null) {
      setState(() => _websiteErrorKey = websiteError);
      _formKey.currentState?.validate();
      return;
    }

    String? website;
    try {
      final sanitised = UserProfile.sanitizeWebsite(_websiteCtrl.text);
      website = sanitised.isEmpty ? null : sanitised;
      setState(() => _websiteErrorKey = null);
    } on FormatException catch (err) {
      setState(() => _websiteErrorKey = err.message);
      _formKey.currentState?.validate();
      return;
    }

    _isSaving.value = true;
    setState(() {});

    Future<SafeResult<String>>? avatarFuture;
    Future<SafeResult<String>>? coverFuture;
    if (_avatarFile != null) {
      avatarFuture = _storageService.uploadUserImage(
        uid: user.uid,
        file: _avatarFile!,
        isCover: false,
      );
    }
    if (_coverFile != null) {
      coverFuture = _storageService.uploadUserImage(
        uid: user.uid,
        file: _coverFile!,
        isCover: true,
      );
    }

    try {
      await Future.wait([
        if (avatarFuture != null) avatarFuture,
        if (coverFuture != null) coverFuture,
      ]);
    } catch (_) {
      // SafeResult already captures errors; ignore.
    }

    String? photoUrl = _currentPhotoUrl;
    String? coverUrl = _currentCoverUrl;

    if (avatarFuture != null) {
      final result = await avatarFuture;
      if (result is SafeSuccess<String>) {
        photoUrl = result.value;
      } else if (result is SafeFailure<String>) {
        _isSaving.value = false;
        setState(() {});
        _showErrorSnack(result.message);
        return;
      }
    }

    if (coverFuture != null) {
      final result = await coverFuture;
      if (result is SafeSuccess<String>) {
        coverUrl = result.value;
      } else if (result is SafeFailure<String>) {
        _isSaving.value = false;
        setState(() {});
        _showErrorSnack(result.message);
        return;
      }
    }

    final profile = UserProfile(
      displayName: _displayNameCtrl.text.trim(),
      username: _usernameCtrl.text.trim(),
      bio: _bioCtrl.text.trim().isNotEmpty ? _bioCtrl.text.trim() : null,
      website: website,
      location: _locationCtrl.text.trim().isNotEmpty
          ? _locationCtrl.text.trim()
          : null,
      birthdate: _birthdate,
      photoURL: photoUrl,
      coverURL: coverUrl,
      showEmail: _showEmail,
      dmPermission: _dmPermission,
    );

    try {
      await _userService.saveProfile(user.uid, profile);
      if (!mounted) return;
      _currentPhotoUrl = photoUrl;
      _currentCoverUrl = coverUrl;
      _avatarFile = null;
      _coverFile = null;
      _avatarPreview = null;
      _coverPreview = null;
      _initialUsername = profile.username;
      _initialDisplayName = profile.displayName;
      _initialBio = profile.bio;
      _initialWebsite = profile.website;
      _initialLocation = profile.location;
      _initialBirthdate = _birthdate;
      _initialShowEmail = _showEmail;
      _initialDmPermission = _dmPermission;
      _isDirty.value = false;
      _isSaving.value = false;
      setState(() {});
      _showSnack('Profile updated successfully ✅');
    } catch (err) {
      if (!mounted) return;
      _isSaving.value = false;
      setState(() {});
      _showErrorSnack(err.toString());
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showErrorSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message.isEmpty ? _t('unexpected_error') : message,
        ),
      ),
    );
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (_isSaving.value) {
      return false;
    }
    if (!_isDirty.value) {
      return true;
    }
    FocusScope.of(context).unfocus();
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_t('discard_changes_title')),
          content: Text(_t('discard_changes_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_t('stay')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_t('discard')),
            ),
          ],
        );
      },
    );
    return shouldDiscard ?? false;
  }

  Future<void> _handleCancel() async {
    final shouldPop = await _confirmDiscardIfNeeded();
    if (shouldPop && mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _handleBackNavigation() async {
    final shouldPop = await _confirmDiscardIfNeeded();
    if (shouldPop && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _onWillPop() async {
    return _confirmDiscardIfNeeded();
  }

  Widget _buildAvailabilityBadge() {
    final theme = Theme.of(context);
    final successColor = theme.colorScheme.tertiary;
    final errorColor = theme.colorScheme.error;
    Widget child;
    switch (_usernameStatus) {
      case _UsernameStatus.checking:
        child = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        break;
      case _UsernameStatus.available:
        child = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: successColor, size: 18),
            const SizedBox(width: 4),
            Text(
              _t('username_ok'),
              style: theme.textTheme.labelSmall?.copyWith(color: successColor),
            ),
          ],
        );
        break;
      case _UsernameStatus.taken:
        child = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel, color: errorColor, size: 18),
            const SizedBox(width: 4),
            Text(
              _t('username_taken'),
              style: theme.textTheme.labelSmall?.copyWith(color: errorColor),
            ),
          ],
        );
        break;
      case _UsernameStatus.invalid:
      case _UsernameStatus.idle:
      default:
        child = const SizedBox.shrink();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: child,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(sizeFactor: animation, child: child),
      ),
    );
  }

  Widget _buildAvatar() {
    ImageProvider? image;
    if (_avatarPreview != null) {
      image = MemoryImage(_avatarPreview!);
    } else if (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) {
      image = CachedNetworkImageProvider(_currentPhotoUrl!);
    }
    final theme = Theme.of(context);
    final hasPendingAvatar = _avatarFile != null;
    final chipColor = theme.colorScheme.secondaryContainer.withOpacity(0.9);
    final chipTextColor = theme.colorScheme.onSecondaryContainer;

    return SizedBox(
      width: 104,
      height: 104,
      child: AbsorbPointer(
        absorbing: _isSaving.value,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _isSaving.value ? 0.6 : 1,
          child: Stack(
            children: [
              Positioned.fill(
                child: CircleAvatar(
                  radius: 52,
                  backgroundColor: theme.colorScheme.surfaceVariant,
                  backgroundImage: image,
                  child: image == null
                      ? Icon(
                          Icons.person,
                          size: 48,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                ),
              ),
              if (hasPendingAvatar)
                PositionedDirectional(
                  top: 4,
                  start: 4,
                  child: Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(_t('unsaved_changes')),
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      color: chipTextColor,
                    ),
                    backgroundColor: chipColor,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              PositionedDirectional(
                bottom: 0,
                end: 4,
                child: Tooltip(
                  message: _t('change_photo'),
                  child: Material(
                    color: theme.colorScheme.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _isSaving.value ? null : _pickAvatar,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.camera_alt,
                          color: theme.colorScheme.onPrimary,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover() {
    Widget child;
    if (_coverPreview != null) {
      child = Image.memory(
        _coverPreview!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else if (_currentCoverUrl != null && _currentCoverUrl!.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: _currentCoverUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
      );
    } else {
      child = Container(
        color: Theme.of(context).colorScheme.surfaceVariant,
        alignment: Alignment.center,
        child: Icon(
          Icons.image,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: 48,
        ),
      );
    }

    final theme = Theme.of(context);
    final hasPendingCover = _coverFile != null;
    final chipColor = theme.colorScheme.secondaryContainer.withOpacity(0.9);
    final chipTextColor = theme.colorScheme.onSecondaryContainer;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: AbsorbPointer(
        absorbing: _isSaving.value,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _isSaving.value ? 0.6 : 1,
          child: Stack(
            children: [
              Positioned.fill(child: child),
              if (hasPendingCover)
                PositionedDirectional(
                  top: 12,
                  end: 12,
                  child: Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(_t('unsaved_changes')),
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      color: chipTextColor,
                    ),
                    backgroundColor: chipColor,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              PositionedDirectional(
                bottom: 12,
                start: 12,
                child: FilledButton.icon(
                  onPressed: _isSaving.value ? null : _pickCover,
                  icon: const Icon(Icons.photo_library_rounded),
                  label: Text(_t('change_cover')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missingAuth = !_loading && _uid == null;

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : missingAuth
            ? Center(child: Text(_t('login_required')))
            : _loadError != null && _loadError != 'no-auth'
                ? Center(child: Text(_t('unexpected_error')))
                : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Card(
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _buildCover(),
                              PositionedDirectional(
                                bottom: -52,
                                end: 24,
                                child: _buildAvatar(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 64),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildAccountStatusSection(theme),
                                  TextFormField(
                                    controller: _displayNameCtrl,
                                    enabled: !_isSaving.value,
                                    decoration: InputDecoration(
                                      labelText: _t('display_name'),
                                    ),
                                    onChanged: (_) {
                                      _updateDirtyState();
                                    },
                                    validator: (value) {
                                      final trimmed = value?.trim() ?? '';
                                      if (trimmed.isEmpty) {
                                        return _t('display_name_required');
                                      }
                                      if (trimmed.length > 40) {
                                        return _t('display_name_too_long');
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      TextFormField(
                                        controller: _usernameCtrl,
                                        enabled: !_isSaving.value,
                                        decoration: InputDecoration(
                                          labelText: '@${_t('username')}',
                                          suffixIcon: Padding(
                                            padding: const EdgeInsetsDirectional.only(end: 8.0),
                                            child: _buildAvailabilityBadge(),
                                          ),
                                          suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                                        ),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(RegExp('[a-z0-9_]')),
                                        ],
                                        onChanged: _onUsernameChanged,
                                        validator: (value) {
                                          final trimmed = value?.trim() ?? '';
                                          if (trimmed.isEmpty) {
                                            return _t('username_required');
                                          }
                                          if (_usernameStatus == _UsernameStatus.invalid &&
                                              _usernameErrorKey != null) {
                                            return _profileEditStrings[_usernameErrorKey!] ?? _usernameErrorKey;
                                          }
                                          if (_usernameStatus == _UsernameStatus.taken) {
                                            return _t('username_taken');
                                          }
                                          return null;
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _bioCtrl,
                                    enabled: !_isSaving.value,
                                    decoration: InputDecoration(labelText: _t('bio')),
                                    maxLines: 4,
                                    maxLength: 160,
                                    onChanged: (_) => _updateDirtyState(),
                                    validator: (value) {
                                      final length = value?.trim().length ?? 0;
                                      if (length > 160) {
                                        return _t('bio_limit');
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _websiteCtrl,
                                    enabled: !_isSaving.value,
                                    decoration: InputDecoration(
                                      labelText: _t('website'),
                                      errorText: _websiteErrorKey == null
                                          ? null
                                          : _profileEditStrings[_websiteErrorKey!] ?? _websiteErrorKey,
                                    ),
                                    keyboardType: TextInputType.url,
                                    onChanged: (value) {
                                      setState(() {
                                        _websiteErrorKey = _validateWebsite(value);
                                      });
                                      _updateDirtyState();
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _locationCtrl,
                                    enabled: !_isSaving.value,
                                    decoration: InputDecoration(labelText: _t('location')),
                                    onChanged: (_) => _updateDirtyState(),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: InputDecorator(
                                          decoration: InputDecoration(
                                            labelText: _t('birthday'),
                                            border: const OutlineInputBorder(),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _formatBirthdate(_birthdate) ?? '—',
                                                style: theme.textTheme.bodyMedium,
                                              ),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    tooltip: _t('pick_birthday'),
                                                    onPressed: _isSaving.value ? null : _pickBirthdate,
                                                    icon: const Icon(Icons.calendar_today),
                                                  ),
                                                  IconButton(
                                                    tooltip: _t('clear_birthday'),
                                                    onPressed: _isSaving.value
                                                        ? null
                                                        : () {
                                                            setState(() => _birthdate = null);
                                                            _updateDirtyState();
                                                          },
                                                    icon: const Icon(Icons.clear),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    _t('privacy_title'),
                                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 12),
                                  SwitchListTile.adaptive(
                                    value: _showEmail,
                                    onChanged: _isSaving.value
                                        ? null
                                        : (value) {
                                            setState(() => _showEmail = value);
                                            _updateDirtyState();
                                          },
                                    title: Text(_t('privacy_show_email')),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      ChoiceChip(
                                        label: Text(_t('privacy_dm_anyone')),
                                        selected: _dmPermission == 'all',
                                        onSelected: _isSaving.value
                                            ? null
                                            : (selected) {
                                                if (selected) {
                                                  setState(() => _dmPermission = 'all');
                                                  _updateDirtyState();
                                                }
                                              },
                                      ),
                                      ChoiceChip(
                                        label: Text(_t('privacy_dm_followers')),
                                        selected: _dmPermission == 'followers',
                                        onSelected: _isSaving.value
                                            ? null
                                            : (selected) {
                                                if (selected) {
                                                  setState(() => _dmPermission = 'followers');
                                                  _updateDirtyState();
                                                }
                                              },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: _isSaveEnabled ? _handleSave : null,
                                          child: _isSaving.value
                                              ? SizedBox(
                                                  height: 20,
                                                  width: 20,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor: AlwaysStoppedAnimation<Color>(
                                                      Theme.of(context).colorScheme.onPrimary,
                                                    ),
                                                  ),
                                                )
                                              : Text(_t('save')),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      TextButton(
                                        onPressed: _isSaving.value
                                            ? null
                                            : () {
                                                _handleCancel();
                                              },
                                        child: Text(_t('cancel')),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                _handleBackNavigation();
              },
            ),
            title: Text(_t('profile_edit_title')),
          ),
          body: body,
        ),
      ),
    );
  }
}
