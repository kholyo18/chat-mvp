import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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

class _UserOpinionPageState extends State<UserOpinionPage> {
  final UserOpinionService _service = UserOpinionService();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _myOpinionError;
  String? _peerOpinionError;
  UserOpinion? _peerOpinion;

  late String _relationshipType;
  late String _perception;
  late Set<String> _likedThings;
  late Set<String> _personalityTraits;
  late int _admirationPercent;
  DateTime? _createdAt;

  static const Map<String, String> _relationshipLabels = <String, String>{
    'none': 'لا شيء',
    'friend': 'صديق',
    'close_friend': 'صديق مقرّب',
    'lover': 'حبيب',
    'spouse': 'زوج / زوجة',
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
    'stubborn': 'عنيد / ة',
    'respectful': 'محترم / ة',
    'kind': 'حنون / ة',
    'romantic': 'رومانسي / ة',
    'strong': 'قوي / ة',
    'smart': 'ذكي / ة',
    'all': 'كل ما سبق',
  };

  @override
  void initState() {
    super.initState();
    _setDefaults();
    _loadOpinions();
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
      }).catchError((error) {
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
      }).catchError((error) {
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
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('الآراء عن ${widget.displayName}'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildForm(context),
              ),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_myOpinionError != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _myOpinionError!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loadOpinions,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
          if (_myOpinionError != null) const SizedBox(height: 16),
          Text(
            'وجهة نظرك عن ${widget.displayName}',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 12),
          _buildRelationshipCard(theme),
          const SizedBox(height: 16),
          _buildPerceptionCard(theme),
          const SizedBox(height: 16),
          _buildLikedThingsCard(theme),
          const SizedBox(height: 16),
          _buildPersonalityCard(theme),
          const SizedBox(height: 16),
          _buildAdmirationCard(theme),
          const SizedBox(height: 24),
          Text(
            'نظرة ${widget.displayName} عنك',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 12),
          _buildPeerOpinionCard(theme),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildRelationshipCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ماذا يكون هذا الشخص بالنسبة لك؟',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: _relationshipLabels.entries.map((entry) {
                final value = entry.key;
                final label = entry.value;
                final selected = _relationshipType == value;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (isSelected) {
                    if (!isSelected) {
                      return;
                    }
                    setState(() {
                      _relationshipType = value;
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerceptionCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'نظرتك لهذا الشخص:',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: _perceptionLabels.entries.map((entry) {
                final value = entry.key;
                final label = entry.value;
                final selected = _perception == value;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (isSelected) {
                    if (!isSelected) {
                      return;
                    }
                    setState(() {
                      _perception = value;
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLikedThingsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ماذا يعجبك في هذا الشخص؟',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: _likedThingsLabels.entries.map((entry) {
                final value = entry.key;
                final label = entry.value;
                final selected = _likedThings.contains(value);
                return FilterChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => _toggleLikedThing(value),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalityCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الصفات التي تعجبك في هذا الشخص:',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: _personalityTraitsLabels.entries.map((entry) {
                final value = entry.key;
                final label = entry.value;
                final selected = _personalityTraits.contains(value);
                return FilterChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => _togglePersonalityTrait(value),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdmirationCard(ThemeData theme) {
    final emoji = _emojiForPercent(_admirationPercent);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'نسبة إعجابك بهذا الشخص:',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_admirationPercent.toString()}%',
                  style: theme.textTheme.titleMedium,
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: child,
                  ),
                  child: Text(
                    emoji,
                    key: ValueKey<String>(emoji),
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
              ],
            ),
            Slider(
              min: 0,
              max: 100,
              divisions: 100,
              value: _admirationPercent.toDouble(),
              label: '${_admirationPercent.toString()}%',
              onChanged: (value) {
                setState(() {
                  _admirationPercent = value.round();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeerOpinionCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _peerOpinionError != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _peerOpinionError!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loadOpinions,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              )
            : _peerOpinion != null
                ? _buildPeerOpinionContent(theme, _peerOpinion!)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'لم يشارك ${widget.displayName} رأيه عنك بعد 🙂',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'عندما يكون جاهزاً سيظهر رأيه هنا.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: () {
                            // TODO: إرسال رسالة تطلب منه مشاركة رأيه.
                          },
                          child: const Text('اطلب منه مشاركة رأيه بلطف'),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildPeerOpinionContent(ThemeData theme, UserOpinion opinion) {
    final relationshipLabel =
        _relationshipLabels[opinion.relationshipType] ?? _relationshipLabels['none']!;
    final perceptionLabel =
        _perceptionLabels[opinion.perception] ?? _perceptionLabels['none']!;
    final likedLabels = _mapValuesToLabels(opinion.likedThings, _likedThingsLabels);
    final traitsLabels =
        _mapValuesToLabels(opinion.personalityTraits, _personalityTraitsLabels);
    final emoji = _emojiForPercent(opinion.admirationPercent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPeerSectionHeader(theme, 'علاقتك من وجهة نظرهم:'),
        Text(
          relationshipLabel,
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 16),
        _buildPeerSectionHeader(theme, 'كيف يرونك:'),
        Text(
          perceptionLabel,
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 16),
        _buildPeerSectionHeader(theme, 'ما الذي يعجبهم فيك:'),
        _buildReadOnlyChips(theme, likedLabels),
        const SizedBox(height: 16),
        _buildPeerSectionHeader(theme, 'الصفات التي يحبونها فيك:'),
        _buildReadOnlyChips(theme, traitsLabels),
        const SizedBox(height: 16),
        _buildPeerSectionHeader(theme, 'نسبة إعجابهم بك:'),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${opinion.admirationPercent}%',
              style: theme.textTheme.titleMedium,
            ),
            Text(
              emoji,
              style: theme.textTheme.headlineMedium,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'آخر تحديث: ${_formatDate(opinion.updatedAt)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }

  Widget _buildPeerSectionHeader(ThemeData theme, String label) {
    return Text(
      label,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      textAlign: TextAlign.right,
    );
  }

  Widget _buildReadOnlyChips(ThemeData theme, List<String> labels) {
    if (labels.length == 1) {
      return Text(
        labels.first,
        style: theme.textTheme.bodyLarge,
        textAlign: TextAlign.right,
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: labels
          .map(
            (label) => Chip(
              label: Text(label),
            ),
          )
          .toList(),
    );
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
    final dateFormatter = DateFormat.yMMMd('ar');
    final timeFormatter = DateFormat.Hm('ar');
    return '${dateFormatter.format(localDate)}، ${timeFormatter.format(localDate)}';
  }

  Widget _buildActions(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isSaving
                  ? null
                  : () {
                      Navigator.of(context).pop();
                    },
              child: const Text('إلغاء'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _isSaving ? null : () => _save(context),
              child: _isSaving
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.onPrimary,
                        ),
                      ),
                    )
                  : const Text('حفظ'),
            ),
          ),
        ],
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
    final messenger = ScaffoldMessenger.of(context);
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
      messenger.showSnackBar(
        const SnackBar(content: Text('تم حفظ نظرتك بنجاح ✅')),
      );
      Navigator.of(context).pop(true);
    } on UserOpinionException {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر حفظ البيانات، حاول مرة أخرى.')),
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
    if (value <= 20) {
      return '😐';
    }
    if (value <= 40) {
      return '🙂';
    }
    if (value <= 70) {
      return '😊';
    }
    if (value <= 90) {
      return '😍';
    }
    return '❤️';
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
}
