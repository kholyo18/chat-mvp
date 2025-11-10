import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show TextDirection;
import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'models/user_opinion.dart';
import 'services/user_opinion_service.dart';

enum _ConnectionMood {
  neutral,
  friendly,
  close,
  romantic,
}

class UserOpinionPage extends StatefulWidget {
  const UserOpinionPage({
    super.key,
    required this.currentUid,
    required this.otherUid,
    required this.displayName,
  });

  final String currentUid;
  final String otherUid;
  final String displayName;

  @override
  State<UserOpinionPage> createState() => _UserOpinionPageState();
}

class _UserOpinionPageState extends State<UserOpinionPage>
    with TickerProviderStateMixin {
  final UserOpinionService _service = UserOpinionService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _showSuccessNotice = false;
  String? _myOpinionError;
  String? _peerOpinionError;
  UserOpinion? _peerOpinion;
  Timer? _successTimer;

  late String _relationshipType;
  late String _perception;
  late Set<String> _likedThings;
  late Set<String> _personalityTraits;
  late int _admirationPercent;
  DateTime? _createdAt;

  late final TabController _tabController;
  late final AnimationController _introController;
  late final Animation<double> _introOpacity;
  late final Animation<Offset> _introOffset;
  late final PageController _pageController;

  int _currentPage = 0;
  int _previousAdmirationPercent = 0;
  bool _saveButtonPulsing = false;
  Timer? _saveButtonTimer;

  static const Map<_ConnectionMood, List<Color>> _headerGradientPalettes = {
    _ConnectionMood.neutral: [Color(0xFFE9EDF3), Color(0xFFF5F6FA)],
    _ConnectionMood.friendly: [Color(0xFFBCE6FF), Color(0xFFD4F8F6)],
    _ConnectionMood.close: [Color(0xFFCFF7E5), Color(0xFFB7EED4)],
    _ConnectionMood.romantic: [Color(0xFFFFD9E8), Color(0xFFFFC3D8)],
  };

  static const Map<_ConnectionMood, List<Color>> _backgroundGradientPalettes = {
    _ConnectionMood.neutral: [Color(0xFFF5F6F8), Color(0xFFECEFF5)],
    _ConnectionMood.friendly: [Color(0xFFF0F8FF), Color(0xFFE6FFFA)],
    _ConnectionMood.close: [Color(0xFFF1FFF6), Color(0xFFE7FFF0)],
    _ConnectionMood.romantic: [Color(0xFFFFF1F6), Color(0xFFFFE5F1)],
  };

  static const Map<_ConnectionMood, Color> _accentColors = {
    _ConnectionMood.neutral: Color(0xFF7A8899),
    _ConnectionMood.friendly: Color(0xFF1F8AC0),
    _ConnectionMood.close: Color(0xFF2AA977),
    _ConnectionMood.romantic: Color(0xFFE85C8B),
  };

  static const Map<String, String> _relationshipLabels = <String, String>{
    'none': 'لا شيء',
    'friend': 'صديق',
    'close_friend': 'صديق مقرّب',
    'lover': 'حبيب/حبيبة',
    'spouse': 'زوج/زوجة',
    'acquaintance': 'معارف',
  };

  static const Map<String, String> _perceptionLabels = <String, String>{
    'none': 'لا شيء',
    'normal': 'عادي',
    'crush': 'إعجاب',
    'special': 'شخص مميز',
  };

  static const Map<String, String> _likedThingsLabels = <String, String>{
    'none': 'لا شيء',
    'courage': 'الشجاعة',
    'honesty': 'الصدق',
    'generosity': 'الكرم',
    'respect': 'الاحترام',
    'trust': 'الثقة',
    'all': 'كل ما سبق',
  };

  static const Map<String, String> _personalityTraitsLabels = <String, String>{
    'none': 'لا شيء',
    'stubborn': 'عنيد/ة',
    'respectful': 'محترم/ة',
    'kind': 'حنون/ة',
    'romantic': 'رومانسي/ة',
    'strong': 'قوي/ة',
    'smart': 'ذكي/ة',
    'all': 'كل ما سبق',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _introOpacity = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    );
    _introOffset = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    ));
    _pageController = PageController(viewportFraction: 0.92);
    _setDefaults();
    _loadOpinions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _introController.dispose();
    _pageController.dispose();
    _successTimer?.cancel();
    _saveButtonTimer?.cancel();
    super.dispose();
  }

  void _setDefaults() {
    _relationshipType = 'none';
    _perception = 'none';
    _likedThings = <String>{'none'};
    _personalityTraits = <String>{'none'};
    _admirationPercent = 0;
    _previousAdmirationPercent = 0;
    _createdAt = null;
  }

  _ConnectionMood get _currentMood {
    final relationshipMood = _moodFromRelationship(_relationshipType);
    final admirationMood = _moodFromPercent(_admirationPercent);
    return _ConnectionMood
        .values[math.max(relationshipMood.index, admirationMood.index)];
  }

  _ConnectionMood _moodFromRelationship(String relationship) {
    switch (relationship) {
      case 'lover':
      case 'spouse':
        return _ConnectionMood.romantic;
      case 'close_friend':
        return _ConnectionMood.close;
      case 'friend':
      case 'acquaintance':
        return _ConnectionMood.friendly;
      default:
        return _ConnectionMood.neutral;
    }
  }

  _ConnectionMood _moodFromPercent(int percent) {
    if (percent <= 25) {
      return _ConnectionMood.neutral;
    }
    if (percent <= 50) {
      return _ConnectionMood.friendly;
    }
    if (percent <= 75) {
      return _ConnectionMood.close;
    }
    return _ConnectionMood.romantic;
  }

  LinearGradient _headerGradientForMood(_ConnectionMood mood) {
    final palette =
        _headerGradientPalettes[mood] ?? _headerGradientPalettes[_ConnectionMood.neutral]!;
    return LinearGradient(
      colors: palette,
      begin: AlignmentDirectional.topStart,
      end: AlignmentDirectional.bottomEnd,
    );
  }

  LinearGradient _backgroundGradientForMood(_ConnectionMood mood) {
    final palette = _backgroundGradientPalettes[mood] ??
        _backgroundGradientPalettes[_ConnectionMood.neutral]!;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: palette,
    );
  }

  LinearGradient _sliderGradientForMood(_ConnectionMood mood) {
    final palette =
        _headerGradientPalettes[mood] ?? _headerGradientPalettes[_ConnectionMood.neutral]!;
    return LinearGradient(
      colors: palette,
      begin: AlignmentDirectional.centerStart,
      end: AlignmentDirectional.centerEnd,
    );
  }

  Color _accentColorForMood(_ConnectionMood mood, ThemeData theme) {
    return _accentColors[mood] ?? theme.colorScheme.primary;
  }

  Future<void> _loadOpinions() async {
    setState(() {
      _isLoading = true;
      _myOpinionError = null;
      _peerOpinionError = null;
      _peerOpinion = null;
    });

    UserOpinion? myOpinion;
    UserOpinion? peerOpinion;
    String? myError;
    String? peerError;

    await Future.wait([
      _service
          .loadMyOpinion(
        currentUid: widget.currentUid,
        peerUid: widget.otherUid,
      )
          .then((value) {
        myOpinion = value;
      }).catchError((_) {
        myError = 'حدث خطأ أثناء تحميل بياناتك. حاول مرة أخرى.';
        return null;
      }),
      _service
          .loadPeerOpinion(
        currentUid: widget.currentUid,
        peerUid: widget.otherUid,
      )
          .then((value) {
        peerOpinion = value;
      }).catchError((_) {
        peerError = 'حدث خطأ أثناء تحميل نظرتهم عنك. حاول مرة أخرى.';
        return null;
      }),
    ]);

    if (!mounted) {
      return;
    }

    setState(() {
      _applyMyOpinion(myOpinion);
      _peerOpinion = peerOpinion;
      _myOpinionError = myError;
      _peerOpinionError = peerError;
      _isLoading = false;
    });
    _introController.forward();
  }

  void _applyMyOpinion(UserOpinion? opinion) {
    if (opinion != null) {
      _relationshipType = opinion.relationshipType;
      _perception = opinion.perception;
      _likedThings = opinion.likedThings.isEmpty
          ? <String>{'none'}
          : opinion.likedThings
              .where((item) => item != 'none' || opinion.likedThings.length == 1)
              .toSet();
      if (_likedThings.length > 1) {
        _likedThings.remove('none');
      }
      _personalityTraits = opinion.personalityTraits.isEmpty
          ? <String>{'none'}
          : opinion.personalityTraits
              .where((item) => item != 'none' || opinion.personalityTraits.length == 1)
              .toSet();
      if (_personalityTraits.length > 1) {
        _personalityTraits.remove('none');
      }
      _previousAdmirationPercent = opinion.admirationPercent;
      _admirationPercent = opinion.admirationPercent;
      _createdAt = opinion.createdAt;
      return;
    }
    _setDefaults();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final title = _localizedText(
      context,
      arabic: 'نظرتك عن ${widget.displayName}',
      english: 'Your view about ${widget.displayName}',
    );
    final mood = _currentMood;
    final backgroundGradient = _backgroundGradientForMood(mood);
    final headerGradient = _headerGradientForMood(mood);
    final accentColor = _accentColorForMood(mood, theme);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(title),
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: backgroundGradient,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              FadeTransition(
                opacity: _introOpacity,
                child: SlideTransition(
                  position: _introOffset,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                              child: _buildHeader(
                                theme,
                                isRtl,
                                headerGradient,
                                accentColor,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: _buildTabSwitcher(theme, isRtl),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: TabBarView(
                                controller: _tabController,
                                physics: const BouncingScrollPhysics(),
                                children: [
                                  _buildMyOpinionTab(theme, isRtl),
                                  _buildPeerOpinionTab(theme, isRtl),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              _buildSuccessNotice(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    bool isRtl,
    LinearGradient gradient,
    Color accentColor,
  ) {
    final initials = widget.displayName.isNotEmpty
        ? widget.displayName.characters.first.toUpperCase()
        : '?';
    final subtitle = _localizedText(
      context,
      arabic: 'وجهة نظرك عن ${widget.displayName}',
      english: 'Share your thoughts about ${widget.displayName}',
    );
    final borderRadius = BorderRadius.circular(32);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: gradient,
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.12),
            blurRadius: 26,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  accentColor.withOpacity(0.25),
                  accentColor.withOpacity(0.05),
                ],
              ),
            ),
            padding: const EdgeInsets.all(4),
            child: CircleAvatar(
              radius: 32,
              backgroundColor: theme.colorScheme.surface.withOpacity(0.9),
              child: Text(
                initials,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  widget.displayName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: isRtl ? TextAlign.right : TextAlign.left,
                ),
                const SizedBox(height: 4),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: 1,
                  child: Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.9),
                    ),
                    textAlign: isRtl ? TextAlign.right : TextAlign.left,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher(ThemeData theme, bool isRtl) {
    final myViewLabel = _localizedText(context, arabic: 'رأيك', english: 'Your view');
    final theirViewLabel =
        _localizedText(context, arabic: 'رأيه فيك', english: 'Their view of you');
    return LayoutBuilder(
      builder: (context, constraints) {
        final indicatorWidth = constraints.maxWidth / 2;
        final alignment = () {
          if (_tabController.index == 0) {
            return isRtl ? Alignment.centerRight : Alignment.centerLeft;
          }
          return isRtl ? Alignment.centerLeft : Alignment.centerRight;
        }();
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withOpacity(0.08),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                alignment: alignment,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: indicatorWidth - 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _TabButton(
                      label: myViewLabel,
                      isSelected: _tabController.index == 0,
                      onTap: () => _tabController.animateTo(0),
                    ),
                  ),
                  Expanded(
                    child: _TabButton(
                      label: theirViewLabel,
                      isSelected: _tabController.index == 1,
                      onTap: () => _tabController.animateTo(1),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMyOpinionTab(ThemeData theme, bool isRtl) {
    if (_myOpinionError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ErrorCard(
                message: _myOpinionError!,
                onRetry: _loadOpinions,
              ),
            ],
          ),
        ),
      );
    }
    final questions = _buildQuestionSteps(context, theme, isRtl);
    final mood = _currentMood;
    final progressGradient = _sliderGradientForMood(mood);
    final accentColor = _accentColorForMood(mood, theme);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              itemCount: questions.length,
              itemBuilder: (context, index) {
                final isCurrent = index == _currentPage;
                final mediaQuery = MediaQuery.of(context);
                final bottomGuard =
                    mediaQuery.viewPadding.bottom + mediaQuery.viewInsets.bottom + 120.0;
                return AnimatedPadding(
                  duration: const Duration(milliseconds: 240),
                  padding: EdgeInsets.only(
                    top: isCurrent ? 0 : 20,
                    bottom: isCurrent ? 12 : 28,
                    right: 8,
                    left: 8,
                  ),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 240),
                    scale: isCurrent ? 1 : 0.96,
                    curve: Curves.easeOut,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 240),
                      opacity: isCurrent ? 1 : 0.65,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final minHeight = math.max(
                            0.0,
                            constraints.maxHeight - bottomGuard,
                          );
                          return SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsetsDirectional.only(
                              top: 12,
                              bottom: bottomGuard,
                              start: 4,
                              end: 4,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: minHeight),
                              child: Align(
                                alignment: Alignment.center,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 420),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    final curved = CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeOutCubic,
                                      reverseCurve: Curves.easeInCubic,
                                    );
                                    return FadeTransition(
                                      opacity: curved,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, 0.08),
                                          end: Offset.zero,
                                        ).animate(curved),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: KeyedSubtree(
                                    key: ValueKey<String>(
                                      'step-$index-${isCurrent ? 'active' : 'idle'}',
                                    ),
                                    child: questions[index](isCurrent),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildProgressBar(
              theme: theme,
              isRtl: isRtl,
              totalSteps: questions.length,
              gradient: progressGradient,
              accentColor: accentColor,
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildPrimaryActions(theme, questions.length),
          ),
        ],
      ),
    );
  }

  List<Widget Function(bool isCurrent)> _buildQuestionSteps(
    BuildContext context,
    ThemeData theme,
    bool isRtl,
  ) {
    return [
      (isCurrent) => _OpinionCard(
            isRtl: isRtl,
            title: _localizedText(
              context,
              arabic: 'ماذا يكون هذا الشخص بالنسبة لك؟',
              english: 'What is this person to you?',
            ),
            child: _buildOptionsWrap(
              theme: theme,
              options: _relationshipLabels,
              isSelected: (value) => _relationshipType == value,
              onSelect: (value) => setState(() {
                _relationshipType = value;
              }),
              multiSelect: false,
            ),
          ),
      (isCurrent) => _OpinionCard(
            isRtl: isRtl,
            title: _localizedText(
              context,
              arabic: 'نظرتك لهذا الشخص:',
              english: 'Your overall view of this person',
            ),
            child: _buildOptionsWrap(
              theme: theme,
              options: _perceptionLabels,
              isSelected: (value) => _perception == value,
              onSelect: (value) => setState(() {
                _perception = value;
              }),
              multiSelect: false,
            ),
          ),
      (isCurrent) => _OpinionCard(
            isRtl: isRtl,
            title: _localizedText(
              context,
              arabic: 'ما الذي يعجبك في هذا الشخص؟',
              english: 'What do you like about this person?',
            ),
            child: _buildOptionsWrap(
              theme: theme,
              options: _likedThingsLabels,
              isSelected: (value) => _likedThings.contains(value),
              onSelect: (value) => _toggleLikedThing(value),
              multiSelect: true,
            ),
          ),
      (isCurrent) => _OpinionCard(
            isRtl: isRtl,
            title: _localizedText(
              context,
              arabic: 'صفات تحبها في هذا الشخص؟',
              english: 'Traits you like in this person',
            ),
            child: _buildOptionsWrap(
              theme: theme,
              options: _personalityTraitsLabels,
              isSelected: (value) => _personalityTraits.contains(value),
              onSelect: (value) => _togglePersonalityTrait(value),
              multiSelect: true,
            ),
          ),
      (isCurrent) => _OpinionCard(
            isRtl: isRtl,
            title: _localizedText(
              context,
              arabic: 'كم تحب هذا الشخص؟',
              english: 'How much do you like this person?',
            ),
            child: _buildAdmirationSlider(
              context,
              theme,
              isActive: isCurrent,
            ),
          ),
    ];
  }

  Widget _buildOptionsWrap({
    required ThemeData theme,
    required Map<String, String> options,
    required bool Function(String value) isSelected,
    required ValueChanged<String> onSelect,
    required bool multiSelect,
  }) {
    final entries = options.entries.toList();
    return Wrap(
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: entries.map((entry) {
        final value = entry.key;
        final label = entry.value;
        final selected = isSelected(value);
        return _SelectableChip(
          label: label,
          selected: selected,
          onTap: () {
            if (!multiSelect && selected) {
              return;
            }
            onSelect(value);
          },
        );
      }).toList(),
    );
  }

  Widget _buildAdmirationSlider(
    BuildContext context,
    ThemeData theme, {
    required bool isActive,
  }) {
    final sliderMood = _moodFromPercent(_admirationPercent);
    final emoji = _emojiForPercent(_admirationPercent);
    final accentColor = _accentColorForMood(sliderMood, theme);
    final gradient = _sliderGradientForMood(sliderMood);
    final direction = Directionality.of(context);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      opacity: isActive ? 1 : 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
        offset: isActive ? Offset.zero : const Offset(0, 0.06),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              textDirection: direction,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TweenAnimationBuilder<int>(
                  tween: IntTween(
                    begin: _previousAdmirationPercent,
                    end: _admirationPercent,
                  ),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Text(
                    '$value%',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedAlign(
                          alignment:
                              Alignment((_admirationPercent / 100) * 2 - 1, 0),
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            transitionBuilder: (child, animation) {
                              final curved = CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutBack,
                              );
                              return FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: 0.85,
                                    end: 1,
                                  ).animate(curved),
                                  child: child,
                                ),
                              );
                            },
                            child: Text(
                              emoji,
                              key: ValueKey<_ConnectionMood>(sliderMood),
                              style: TextStyle(
                                fontSize: 36,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: accentColor),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              builder: (context, animatedColor, child) {
                final resolvedColor = animatedColor ?? accentColor;
                return SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 8,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 11),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 22),
                    trackShape: _GradientSliderTrackShape(
                      gradient: gradient,
                      backgroundColor:
                          theme.colorScheme.surfaceVariant.withOpacity(0.35),
                    ),
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    thumbColor: resolvedColor,
                    overlayColor: resolvedColor.withOpacity(0.12),
                  ),
                  child: Slider(
                    value: _admirationPercent.toDouble(),
                    min: 0,
                    max: 100,
                    onChanged: (value) {
                      setState(() {
                        _previousAdmirationPercent = _admirationPercent;
                        _admirationPercent = value.round();
                      });
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar({
    required ThemeData theme,
    required bool isRtl,
    required int totalSteps,
    required LinearGradient gradient,
    required Color accentColor,
  }) {
    final progress = totalSteps == 0 ? 0.0 : (_currentPage + 1) / totalSteps;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeInOutCubic,
      builder: (context, value, child) {
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: theme.colorScheme.surface.withOpacity(0.86),
            boxShadow: [
              BoxShadow(
                color: accentColor.withOpacity(0.1),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 12,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                    ),
                  ),
                  Align(
                    alignment:
                        isRtl ? Alignment.centerRight : Alignment.centerLeft,
                    child: FractionallySizedBox(
                      alignment:
                          isRtl ? Alignment.centerRight : Alignment.centerLeft,
                      widthFactor: value,
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: gradient),
                      ),
                    ),
                  ),
                  Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                            fontWeight: FontWeight.w600,
                          ) ??
                          TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                            fontWeight: FontWeight.w600,
                          ),
                      child: Text('${_currentPage + 1}/$totalSteps'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPrimaryActions(ThemeData theme, int pageCount) {
    final isLastPage = _currentPage == pageCount - 1;
    final saveLabel = _localizedText(context, arabic: 'حفظ', english: 'Save');
    final nextLabel = _localizedText(context, arabic: 'التالي', english: 'Next');
    final backLabel = _localizedText(context, arabic: 'السابق', english: 'Previous');
    return Row(
      children: [
        if (_currentPage > 0)
          Expanded(
            child: OutlinedButton(
              onPressed: () => _animateToPage(_currentPage - 1),
              child: Text(backLabel),
            ),
          ),
        if (_currentPage > 0) const SizedBox(width: 12),
        Expanded(
          child: AnimatedScale(
            scale: isLastPage && _saveButtonPulsing ? 1.04 : 1.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: FilledButton(
              onPressed: _isSaving
                  ? null
                  : () {
                      if (isLastPage) {
                        _triggerSaveButtonPulse();
                        _save(context);
                      } else {
                        _animateToPage(_currentPage + 1);
                      }
                    },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _isSaving
                    ? SizedBox(
                        key: const ValueKey('saving'),
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.onPrimary,
                          ),
                        ),
                      )
                    : Text(
                        isLastPage ? saveLabel : nextLabel,
                        key: ValueKey<String>(isLastPage ? 'save' : 'next'),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _animateToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  void _triggerSaveButtonPulse() {
    _saveButtonTimer?.cancel();
    setState(() {
      _saveButtonPulsing = true;
    });
    _saveButtonTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _saveButtonPulsing = false;
      });
    });
  }

  Widget _buildPeerOpinionTab(ThemeData theme, bool isRtl) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: () {
        if (_peerOpinionError != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _ErrorCard(
                message: _peerOpinionError!,
                onRetry: _loadOpinions,
              ),
            ),
          );
        }
        if (_peerOpinion == null) {
          final empty = _localizedText(
            context,
            arabic: 'لم يقم هذا الشخص بعد بكتابة رأيه عنك.',
            english: 'This person hasn’t shared their view about you yet.',
          );
          return Center(
            child: AnimatedOpacity(
              opacity: 1,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeInOut,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  empty,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final peer = _peerOpinion!;
        final myRelationshipLabel =
            _relationshipLabels[_relationshipType] ?? _relationshipLabels['none']!;
        final theirRelationshipLabel =
            _relationshipLabels[peer.relationshipType] ?? _relationshipLabels['none']!;
        final myPerceptionLabel =
            _perceptionLabels[_perception] ?? _perceptionLabels['none']!;
        final theirPerceptionLabel =
            _perceptionLabels[peer.perception] ?? _perceptionLabels['none']!;
        final myLiked =
            _mapValuesToLabels(_orderedLikedThings(), _likedThingsLabels).join('، ');
        final theirLiked =
            _mapValuesToLabels(peer.likedThings, _likedThingsLabels).join('، ');
        final myTraits =
            _mapValuesToLabels(_orderedPersonalityTraits(), _personalityTraitsLabels)
                .join('، ');
        final theirTraits = _mapValuesToLabels(
          peer.personalityTraits,
          _personalityTraitsLabels,
        ).join('، ');
        final admirationMood = _moodFromPercent(peer.admirationPercent);
        final admirationEmoji = _emojiForPercent(peer.admirationPercent);
        final admirationColor = _accentColorForMood(admirationMood, theme);
        final admirationGradient = _sliderGradientForMood(admirationMood);
        final updated = _formatDate(peer.updatedAt);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _ReadOnlyCard(
              isRtl: isRtl,
              title: _localizedText(
                context,
                arabic: 'ماذا تكون بالنسبة له؟',
                english: 'What are you to them?',
              ),
              value: theirRelationshipLabel,
              comparison: _localizedText(
                context,
                arabic: 'أنت قلت: $myRelationshipLabel',
                english: 'You said: $myRelationshipLabel',
              ),
            ),
            _ReadOnlyCard(
              isRtl: isRtl,
              title: _localizedText(
                context,
                arabic: 'كيف يرونك؟',
                english: 'How do they see you?',
              ),
              value: theirPerceptionLabel,
              comparison: _localizedText(
                context,
                arabic: 'أنت قلت: $myPerceptionLabel',
                english: 'You said: $myPerceptionLabel',
              ),
            ),
            _ReadOnlyCard(
              isRtl: isRtl,
              title: _localizedText(
                context,
                arabic: 'ما الذي يعجبهم فيك؟',
                english: 'What do they like about you?',
              ),
              value: theirLiked,
              comparison: _localizedText(
                context,
                arabic: 'أنت قلت: $myLiked',
                english: 'You said: $myLiked',
              ),
            ),
            _ReadOnlyCard(
              isRtl: isRtl,
              title: _localizedText(
                context,
                arabic: 'صفات يحبونها فيك؟',
                english: 'Traits they like about you',
              ),
              value: theirTraits,
              comparison: _localizedText(
                context,
                arabic: 'أنت قلت: $myTraits',
                english: 'You said: $myTraits',
              ),
            ),
            _ReadOnlyCard(
              isRtl: isRtl,
              title: _localizedText(
                context,
                arabic: 'نسبة إعجابهم بك',
                english: 'How much they like you',
              ),
              valueWidget: Column(
                crossAxisAlignment:
                    isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${peer.admirationPercent}%',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        admirationEmoji,
                        style: TextStyle(fontSize: 32, color: admirationColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _GradientProgressBar(
                    progress: peer.admirationPercent / 100,
                    gradient: admirationGradient,
                    backgroundColor:
                        theme.colorScheme.surfaceVariant.withOpacity(0.3),
                    isRtl: isRtl,
                  ),
                ],
              ),
              comparison: _localizedText(
                context,
                arabic: 'أنت قلت: ${_admirationPercent}%',
                english: 'You said: ${_admirationPercent}%',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _localizedText(
                context,
                arabic: 'آخر تحديث: $updated',
                english: 'Last updated: $updated',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
              textAlign: isRtl ? TextAlign.right : TextAlign.left,
            ),
          ],
        );
      }(),
    );
  }

  Widget _buildSuccessNotice(ThemeData theme) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            offset: _showSuccessNotice ? Offset.zero : const Offset(0, 0.3),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _showSuccessNotice ? 1 : 0,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.16),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Text(
                      _localizedText(
                        context,
                        arabic: 'تم حفظ نظرتك بنجاح ✅',
                        english: 'Your view was saved successfully ✅',
                      ),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleLikedThing(String value) {
    setState(() {
      if (value == 'none') {
        _likedThings = <String>{'none'};
        return;
      }
      final selections = Set<String>.from(_likedThings);
      if (selections.contains(value)) {
        selections.remove(value);
      } else {
        selections.add(value);
      }
      selections.remove('none');
      if (selections.isEmpty) {
        selections.add('none');
      }
      _likedThings = selections;
    });
  }

  void _togglePersonalityTrait(String value) {
    setState(() {
      if (value == 'none') {
        _personalityTraits = <String>{'none'};
        return;
      }
      final selections = Set<String>.from(_personalityTraits);
      if (selections.contains(value)) {
        selections.remove(value);
      } else {
        selections.add(value);
      }
      selections.remove('none');
      if (selections.isEmpty) {
        selections.add('none');
      }
      _personalityTraits = selections;
    });
  }

  Future<void> _save(BuildContext context) async {
    setState(() {
      _isSaving = true;
    });
    final now = DateTime.now().toUtc();
    final createdAt = _createdAt ?? now;
    final opinion = UserOpinion(
      relationshipType: _relationshipType,
      perception: _perception,
      likedThings: _orderedLikedThings(),
      personalityTraits: _orderedPersonalityTraits(),
      admirationPercent: _admirationPercent,
      createdAt: createdAt,
      updatedAt: now,
    );
    try {
      await _service.saveOpinion(
        currentUid: widget.currentUid,
        otherUid: widget.otherUid,
        opinion: opinion,
      );
      if (!mounted) {
        return;
      }
      HapticFeedback.mediumImpact();
      setState(() {
        _showSuccessNotice = true;
      });
      final successMessage = _localizedText(
        context,
        arabic: 'تم حفظ نظرتك ❤️',
        english: 'Your view has been saved ❤️',
      );
      final snackTheme = Theme.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: snackTheme.colorScheme.surface.withOpacity(0.95),
            duration: const Duration(seconds: 2),
            content: Text(
              successMessage,
              style: snackTheme.textTheme.bodyMedium?.copyWith(
                color: snackTheme.colorScheme.onSurface,
              ),
            ),
          ),
        );
      _successTimer?.cancel();
      _successTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() {
            _showSuccessNotice = false;
          });
        }
      });
      await Future.delayed(const Duration(milliseconds: 480));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on UserOpinionException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              context,
              arabic: 'تعذر حفظ البيانات، حاول مرة أخرى.',
              english: 'Couldn\'t save your view. Please try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _createdAt = createdAt;
        });
      }
    }
  }

  String _emojiForPercent(int value) {
    if (value <= 25) {
      return '😐';
    }
    if (value <= 50) {
      return '🙂';
    }
    if (value <= 75) {
      return '😍';
    }
    return '❤️‍🔥';
  }

  List<String> _orderedLikedThings() {
    if (_likedThings.contains('none') && _likedThings.length == 1) {
      return const <String>['none'];
    }
    if (_likedThings.isEmpty) {
      return const <String>['none'];
    }
    return _likedThingsLabels.keys
        .where((key) => key != 'none' && _likedThings.contains(key))
        .toList();
  }

  List<String> _orderedPersonalityTraits() {
    if (_personalityTraits.contains('none') && _personalityTraits.length == 1) {
      return const <String>['none'];
    }
    if (_personalityTraits.isEmpty) {
      return const <String>['none'];
    }
    return _personalityTraitsLabels.keys
        .where((key) => key != 'none' && _personalityTraits.contains(key))
        .toList();
  }

  List<String> _mapValuesToLabels(
    List<String> values,
    Map<String, String> labels,
  ) {
    if (values.isEmpty) {
      return <String>[labels['none'] ?? 'لا شيء'];
    }
    if (values.contains('none') && values.length == 1) {
      return <String>[labels['none'] ?? 'لا شيء'];
    }
    final resolved = values
        .where((value) => value != 'none')
        .map((value) => labels[value] ?? value)
        .toList();
    if (resolved.isEmpty) {
      return <String>[labels['none'] ?? 'لا شيء'];
    }
    return resolved;
  }

  String _formatDate(DateTime date) {
    final localDate = date.toLocal();
    final locale = Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'ar';
    final dateFormatter = intl.DateFormat.yMMMd(locale);
    final timeFormatter = intl.DateFormat.Hm(locale);
    return '${dateFormatter.format(localDate)}, ${timeFormatter.format(localDate)}';
  }

  String _localizedText(
    BuildContext context, {
    required String arabic,
    required String english,
  }) {
    final locale = Localizations.maybeLocaleOf(context)?.languageCode;
    final isArabic =
        locale == 'ar' || Directionality.of(context) == TextDirection.rtl;
    return isArabic ? arabic : english;
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: theme.textTheme.titleMedium!.copyWith(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            child: Center(child: Text(label)),
          ),
        ),
      ),
    );
  }
}

class _OpinionCard extends StatelessWidget {
  const _OpinionCard({
    required this.title,
    required this.child,
    required this.isRtl,
  });

  final String title;
  final Widget child;
  final bool isRtl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(30);
    return Card(
      color: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.surface.withOpacity(0.97),
              theme.colorScheme.surfaceVariant.withOpacity(0.75),
            ],
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withOpacity(0.08),
              blurRadius: 24,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: isRtl ? TextAlign.right : TextAlign.left,
              ),
              const SizedBox(height: 22),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectableChip extends StatelessWidget {
  const _SelectableChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(22);
    final gradient = LinearGradient(
      colors: [
        theme.colorScheme.primary.withOpacity(0.95),
        theme.colorScheme.secondary.withOpacity(0.7),
      ],
      begin: AlignmentDirectional.topStart,
      end: AlignmentDirectional.bottomEnd,
    );
    final backgroundColor = theme.colorScheme.surface.withOpacity(0.94);
    return AnimatedScale(
      scale: selected ? 1.04 : 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOutCubic,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: selected ? gradient : null,
              color: selected ? null : backgroundColor,
              border: Border.all(
                color: selected
                    ? Colors.transparent
                    : theme.colorScheme.primary.withOpacity(0.28),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.24),
                        blurRadius: 22,
                        offset: const Offset(0, 12),
                      ),
                    ]
                  : const [],
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: theme.textTheme.titleMedium!.copyWith(
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.primary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientProgressBar extends StatelessWidget {
  const _GradientProgressBar({
    required this.progress,
    required this.gradient,
    required this.backgroundColor,
    required this.isRtl,
  });

  final double progress;
  final LinearGradient gradient;
  final Color backgroundColor;
  final bool isRtl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 10,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final value = progress.clamp(0.0, 1.0);
            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: backgroundColor),
                  ),
                ),
                Align(
                  alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
                  child: FractionallySizedBox(
                    alignment:
                        isRtl ? Alignment.centerRight : Alignment.centerLeft,
                    widthFactor: value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: gradient),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GradientSliderTrackShape extends SliderTrackShape {
  const _GradientSliderTrackShape({
    required this.gradient,
    required this.backgroundColor,
  });

  final LinearGradient gradient;
  final Color backgroundColor;

  static const RoundedRectSliderTrackShape _baseTrackShape =
      RoundedRectSliderTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    return _baseTrackShape.getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final Rect trackRect = _baseTrackShape.getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final double trackRadiusValue = trackRect.height / 2;
    final Radius trackRadius = Radius.circular(trackRadiusValue);
    final RRect trackRRect = RRect.fromRectAndRadius(trackRect, trackRadius);

    final Canvas canvas = context.canvas;
    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.grey.shade300;
    canvas.drawRRect(trackRRect, inactivePaint);

    final double clampedThumb = thumbCenter.dx.clamp(
      trackRect.left,
      trackRect.right,
    );
    if (clampedThumb <= trackRect.left) {
      return;
    }

    final double? rawSecondary = secondaryOffset?.dx;
    if (rawSecondary != null) {
      final double clampedSecondary = rawSecondary.clamp(
        trackRect.left,
        trackRect.right,
      );
      final double secondaryStart = math.min(clampedThumb, clampedSecondary);
      final double secondaryEnd = math.max(clampedThumb, clampedSecondary);
      if (secondaryEnd > secondaryStart) {
        final Rect secondaryRect = Rect.fromLTRB(
          secondaryStart,
          trackRect.top,
          secondaryEnd,
          trackRect.bottom,
        );
        final Paint secondaryPaint = Paint()
          ..color = (sliderTheme.activeTrackColor ??
                  sliderTheme.thumbColor ??
                  backgroundColor)
              .withOpacity(0.25);
        canvas.drawRRect(
          RRect.fromRectAndRadius(secondaryRect, trackRadius),
          secondaryPaint,
        );
      }
    }

    final Rect activeRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      clampedThumb,
      trackRect.bottom,
    );
    final RRect activeRRect = RRect.fromRectAndRadius(activeRect, trackRadius);

    final List<Color> gradientColors = gradient.colors;
    final Color activeBaseColor = sliderTheme.activeTrackColor ??
        sliderTheme.thumbColor ??
        (gradientColors.isNotEmpty ? gradientColors.last : backgroundColor);
    final Color lightColor =
        Color.lerp(activeBaseColor, Colors.white, 0.45) ?? activeBaseColor;
    final Color strongColor = gradientColors.isNotEmpty
        ? gradientColors.last
        : activeBaseColor;

    final bool isRtl = textDirection == TextDirection.rtl;
    final Paint activePaint = Paint()
      ..shader = LinearGradient(
        begin: isRtl ? Alignment.centerRight : Alignment.centerLeft,
        end: isRtl ? Alignment.centerLeft : Alignment.centerRight,
        colors: <Color>[lightColor, strongColor],
      ).createShader(activeRect);

    canvas.drawRRect(activeRRect, activePaint);
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: Text(
                _localizedStaticText(
                  context,
                  arabic: 'إعادة المحاولة',
                  english: 'Try again',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyCard extends StatelessWidget {
  const _ReadOnlyCard({
    required this.title,
    this.value,
    this.valueWidget,
    this.comparison,
    required this.isRtl,
  });

  final String title;
  final String? value;
  final Widget? valueWidget;
  final String? comparison;
  final bool isRtl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(26);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.surface.withOpacity(0.96),
              theme.colorScheme.surfaceVariant.withOpacity(0.72),
            ],
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
          child: Column(
            crossAxisAlignment:
                isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: isRtl ? TextAlign.right : TextAlign.left,
              ),
              const SizedBox(height: 14),
              if (valueWidget != null)
                valueWidget!
              else if (value != null)
                Text(
                  value!,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: isRtl ? TextAlign.right : TextAlign.left,
                ),
              if (comparison != null) ...[
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    comparison!,
                    key: ValueKey<String>(comparison!),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                    ),
                    textAlign: isRtl ? TextAlign.right : TextAlign.left,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _localizedStaticText(
  BuildContext context, {
  required String arabic,
  required String english,
}) {
  final locale = Localizations.maybeLocaleOf(context)?.languageCode;
  final isArabic = locale == 'ar' || Directionality.of(context) == TextDirection.rtl;
  return isArabic ? arabic : english;
}
