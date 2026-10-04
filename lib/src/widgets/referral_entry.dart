import 'dart:async';

import 'package:flutter/material.dart';

import '../client.dart';
import '../models.dart';
import 'creator_code_input.dart';
import 'labels.dart';
import 'theme.dart';

enum _EntryPhase { checking, hidden, collapsed, expanded }

/// 初回画面の控えめな入口。clipboardReader を渡した場合のみ読み取る。
class ReferralEntry extends StatefulWidget {
  const ReferralEntry({
    super.key,
    this.clipboardReader,
    this.rcAppUserId,
    this.isActiveSubscriber,
    this.labels = const ReferralEntryLabels(),
    this.inputLabels = const CreatorCodeLabels(),
    this.theme = const GoAlongTheme(),
    this.onApplied,
  });

  final ClipboardReader? clipboardReader;
  final String? rcAppUserId;
  final ActiveSubscriberCheck? isActiveSubscriber;
  final ReferralEntryLabels labels;
  final CreatorCodeLabels inputLabels;
  final GoAlongTheme theme;
  final ValueChanged<Creator?>? onApplied;

  @override
  State<ReferralEntry> createState() => _ReferralEntryState();
}

class _ReferralEntryState extends State<ReferralEntry> {
  _EntryPhase _phase = _EntryPhase.checking;
  String? _clipboardCode;

  @override
  void initState() {
    super.initState();
    unawaited(_decide());
  }

  Future<void> _decide() async {
    try {
      if (await GoAlong.hasAppliedReferralLocally()) {
        _setPhase(_EntryPhase.hidden);
        return;
      }
      if (!mounted) return;
      if (await GoAlong.hasActiveSubscription(
        isActiveSubscriber: widget.isActiveSubscriber,
      )) {
        _setPhase(_EntryPhase.hidden);
        return;
      }
      if (!mounted) return;
      final reader = widget.clipboardReader;
      if (reader != null) {
        try {
          final text = await reader();
          if (!mounted) return;
          final code = text == null ? null : GoAlong.extractCode(text);
          if (code != null) {
            _clipboardCode = code;
            _setPhase(_EntryPhase.expanded);
            return;
          }
        } catch (_) {
          // OS の許可拒否などは手入力の入口へフォールバック。
        }
      }
      if (!mounted) return;
      final enabled = await GoAlong.referralEntryEnabled();
      _setPhase(enabled ? _EntryPhase.collapsed : _EntryPhase.hidden);
    } catch (_) {
      _setPhase(_EntryPhase.hidden);
    }
  }

  void _setPhase(_EntryPhase phase) {
    if (mounted) setState(() => _phase = phase);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme.resolve(context);
    return switch (_phase) {
      _EntryPhase.checking || _EntryPhase.hidden => const SizedBox.shrink(),
      _EntryPhase.collapsed => TextButton(
          style: TextButton.styleFrom(
            foregroundColor: theme.secondaryTextColor,
            minimumSize: const Size(44, 44),
          ),
          onPressed: () => _setPhase(_EntryPhase.expanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(widget.labels.collapsed)),
              const Icon(Icons.expand_more, size: 18),
            ],
          ),
        ),
      _EntryPhase.expanded => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardBackground,
            borderRadius: BorderRadius.circular(theme.cornerRadius + 4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.labels.title,
                      style: theme.titleStyle?.copyWith(color: theme.textColor),
                    ),
                  ),
                  IconButton(
                    tooltip: widget.labels.close,
                    color: theme.secondaryTextColor,
                    onPressed: () => _setPhase(_EntryPhase.collapsed),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              CreatorCodeInput(
                initialCode: _clipboardCode ?? '',
                method: _clipboardCode == null
                    ? ApplyMethod.code
                    : ApplyMethod.clipboard,
                rcAppUserId: widget.rcAppUserId,
                isActiveSubscriber: widget.isActiveSubscriber,
                labels: widget.inputLabels,
                theme: widget.theme,
                showsTitle: false,
                onApplied: (creator) {
                  _setPhase(_EntryPhase.hidden);
                  widget.onApplied?.call(creator);
                },
              ),
            ],
          ),
        ),
    };
  }
}
