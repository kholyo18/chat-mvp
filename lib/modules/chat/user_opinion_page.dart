import 'dart:ui' as ui;
import 'dart:async';

import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'models/user_opinion.dart';
import 'services/user_opinion_service.dart';

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
    super.dispose();
  }

  void _setDefaults() {
    _relationshipType = 'none';
    _perception = 'none';
    _likedThings = <String>{'none'};
    _personalityTraits = <String>{'none'};
    _admirationPercent = 0;
    _createdAt = null;
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
      _admirationPercent = opinion.admirationPercent;
      _createdAt = opinion.createdAt;
      return;
    }
    _setDefaults();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = Directionality.of(context) == ui.TextDirection.rtl;
    final title = _localizedText(
      context,
      arabic: 'نظرتك عن ${widget.displayName}',
      english: 'Your view about ${widget.displayName}',
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(title),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF1F0FF),
              Color(0xFFFDF4F6),
            ],
          ),
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
                              child: _buildHeader(theme, isRtl),
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

  Widget _buildHeader(ThemeData theme, bool isRtl) {
    final initials = widget.displayName.isNotEmpty
        ? widget.displayName.characters.first.toUpperCase()
        : '?';
    final subtitle = _localizedText(
      context,
      arabic: 'وجهة نظرك عن ${widget.displayName}',
      english: 'Share your thoughts about ${widget.displayName}',
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withOpacity(0.12),
            theme.colorScheme.secondary.withOpacity(0.08),
          ],
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              initials,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
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
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: isRtl ? TextAlign.right : TextAlign.left,
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
    final questions = _buildQuestionCards(theme, isRtl);
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
                      child: questions[index],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildPageIndicator(theme, questions.length),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildPrimaryActions(theme, questions.length),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildQuestionCards(ThemeData theme, bool isRtl) {
    return [
      _OpinionCard(
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
      _OpinionCard(
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
      _OpinionCard(
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
      _OpinionCard(
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
      _OpinionCard(
        isRtl: isRtl,
        title: _localizedText(
          context,
          arabic: 'كم تحب هذا الشخص؟',
          english: 'How much do you like this person?',
        ),
        child: _buildAdmirationSlider(theme),
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
        return _AnimatedOptionChip(
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

  Widget _buildAdmirationSlider(ThemeData theme) {
    final percentLabel = '${_admirationPercent.round()}%';
    final emoji = _emojiForPercent(_admirationPercent);
    final color = _colorForPercent(_admirationPercent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axis: Axis.horizontal,
                  child: child,
                ),
              ),
              child: Text(
                percentLabel,
                key: ValueKey<String>(percentLabel),
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
                  children: [
                    AnimatedAlign(
                      alignment: Alignment((_admirationPercent / 100) * 2 - 1, 0),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 36),
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
          tween: ColorTween(end: color),
          duration: const Duration(milliseconds: 260),
          builder: (context, animatedColor, child) {
            final trackColor = animatedColor ?? color;
            return SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                activeTrackColor: trackColor,
                inactiveTrackColor: trackColor.withOpacity(0.2),
                thumbColor: trackColor,
                overlayColor: trackColor.withOpacity(0.1),
              ),
              child: Slider(
                value: _admirationPercent.toDouble(),
                min: 0,
                max: 100,
                onChanged: (value) {
                  setState(() {
                    _admirationPercent = value.round();
                  });
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPageIndicator(ThemeData theme, int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isCurrent = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 8,
          width: isCurrent ? 28 : 10,
          decoration: BoxDecoration(
            color: isCurrent
                ? theme.colorScheme.primary.withOpacity(0.7)
                : theme.colorScheme.primary.withOpacity(0.25),
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
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
              onPressed: () {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                );
              },
              child: Text(backLabel),
            ),
          ),
        if (_currentPage > 0) const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: _isSaving
                ? null
                : () {
                    if (isLastPage) {
                      _save(context);
                    } else {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                      );
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
      ],
    );
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
        final admirationEmoji = _emojiForPercent(peer.admirationPercent);
        final admirationColor = _colorForPercent(peer.admirationPercent);
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
                        style: const TextStyle(fontSize: 32),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 8,
                      child: LinearProgressIndicator(
                        value: peer.admirationPercent / 100,
                        backgroundColor:
                            theme.colorScheme.primary.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(admirationColor),
                      ),
                    ),
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
                color: theme.colorScheme.onSurfaceVariant,
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
    if (value <= 30) {
      return '😐';
    }
    if (value <= 60) {
      return '🙂';
    }
    if (value <= 90) {
      return '😍';
    }
    return '❤️‍🔥';
  }

  Color _colorForPercent(int value) {
    if (value <= 30) {
      return Color.lerp(Colors.grey, Colors.blueAccent, value / 30) ?? Colors.grey;
    }
    if (value <= 60) {
      return Color.lerp(
            Colors.blueAccent,
            Colors.pinkAccent,
            (value - 30) / 30,
          ) ??
          Colors.blueAccent;
    }
    if (value <= 90) {
      return Color.lerp(
            Colors.pinkAccent,
            Colors.redAccent,
            (value - 60) / 30,
          ) ??
          Colors.pinkAccent;
    }
    return Color.lerp(
          Colors.redAccent,
          Colors.red,
          (value - 90) / 10,
        ) ??
        Colors.redAccent;
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
    final dateFormatter = DateFormat.yMMMd(locale);
    final timeFormatter = DateFormat.Hm(locale);
    return '${dateFormatter.format(localDate)}, ${timeFormatter.format(localDate)}';
  }

  String _localizedText(
    BuildContext context, {
    required String arabic,
    required String english,
  }) {
    final locale = Localizations.maybeLocaleOf(context)?.languageCode;
    final isArabic = locale == 'ar' || Directionality.of(context) == ui.TextDirection.rtl;
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
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: theme.colorScheme.onSurface,
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
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
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _AnimatedOptionChip extends StatelessWidget {
  const _AnimatedOptionChip({
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
    return AnimatedScale(
      scale: selected ? 1.03 : 1,
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: selected
                  ? theme.colorScheme.primary.withOpacity(0.12)
                  : theme.colorScheme.surface,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
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
            const SizedBox(height: 12),
            if (valueWidget != null)
              valueWidget!
            else if (value != null)
              Text(
                value!,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: isRtl ? TextAlign.right : TextAlign.left,
              ),
            if (comparison != null) ...[
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  comparison!,
                  key: ValueKey<String>(comparison!),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: isRtl ? TextAlign.right : TextAlign.left,
                ),
              ),
            ],
          ],
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
  final isArabic = locale == 'ar' || Directionality.of(context) == ui.TextDirection.rtl;
  return isArabic ? arabic : english;
}
