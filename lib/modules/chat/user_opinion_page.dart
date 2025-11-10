import 'package:flutter/material.dart';

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
  String? _loadError;

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
    _loadOpinion();
  }

  void _setDefaults() {
    _relationshipType = 'none';
    _perception = 'none';
    _likedThings = <String>{'none'};
    _personalityTraits = <String>{'none'};
    _admirationPercent = 0;
    _createdAt = null;
  }

  Future<void> _loadOpinion() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final opinion = await _service.getOpinion(
        currentUid: widget.currentUid,
        otherUid: widget.otherUid,
      );
      if (!mounted) {
        return;
      }
      setState(() {
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
        } else {
          _setDefaults();
        }
      });
    } on UserOpinionException {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = 'حدث خطأ أثناء تحميل البيانات. حاول مرة أخرى.';
        _setDefaults();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('نظرتك عن ${widget.displayName}'),
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
          if (_loadError != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _loadError!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loadOpinion,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
          if (_loadError != null) const SizedBox(height: 16),
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
