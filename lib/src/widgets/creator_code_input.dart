import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import 'creator_code_controller.dart';
import 'labels.dart';
import 'theme.dart';

/// インライン、ダイアログ、ボトムシートに配置できる紹介コード入力欄。
/// 紹介者名や取消 UI は表示しない。取消には GoAlong.removeReferral を使う。
class CreatorCodeInput extends StatefulWidget {
  const CreatorCodeInput({
    super.key,
    this.controller,
    this.initialCode = '',
    this.method = ApplyMethod.code,
    this.rcAppUserId,
    this.isActiveSubscriber,
    this.labels = const CreatorCodeLabels(),
    this.theme = const GoAlongTheme(),
    this.showsTitle = true,
    this.onApplied,
    this.onSkip,
  });

  /// 渡した controller は呼び出し元で dispose する。
  final CreatorCodeController? controller;
  final String initialCode;
  final ApplyMethod method;
  final String? rcAppUserId;
  final ActiveSubscriberCheck? isActiveSubscriber;
  final CreatorCodeLabels labels;
  final GoAlongTheme theme;
  final bool showsTitle;
  final ValueChanged<Creator?>? onApplied;
  final VoidCallback? onSkip;

  @override
  State<CreatorCodeInput> createState() => _CreatorCodeInputState();
}

class _CreatorCodeInputState extends State<CreatorCodeInput> {
  late CreatorCodeController _model;
  late TextEditingController _text;
  late CreatorCodePhase _lastPhase;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _model = widget.controller ??
        CreatorCodeController(
          code: widget.initialCode,
          method: widget.method,
          rcAppUserId: widget.rcAppUserId,
          isActiveSubscriber: widget.isActiveSubscriber,
        );
    _text = TextEditingController(text: _model.code);
    _lastPhase = _model.phase;
    _model.addListener(_changed);
    unawaited(_model.loadCurrentReferral());
  }

  @override
  void didUpdateWidget(CreatorCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _model.removeListener(_changed);
      if (oldWidget.controller == null) _model.dispose();
      _text.dispose();
      _attach();
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_text.text != _model.code) {
      _text.value = TextEditingValue(
        text: _model.code,
        selection: TextSelection.collapsed(offset: _model.code.length),
      );
    }
    final completed = _model.phase == CreatorCodePhase.done &&
        _lastPhase != CreatorCodePhase.done;
    _lastPhase = _model.phase;
    setState(() {});
    if (completed) widget.onApplied?.call(_model.creator);
  }

  @override
  void dispose() {
    _model.removeListener(_changed);
    if (widget.controller == null) _model.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final theme = widget.theme.resolve(context);
    final phase = _model.phase;
    final current = _model.current;
    final alreadyApplied = current is ReferralApplied &&
        phase == CreatorCodePhase.idle &&
        _model.code.isEmpty;
    return DefaultTextStyle.merge(
      style: TextStyle(color: theme.textColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_model.isLoadingCurrent)
            _progress(labels.checking, theme)
          else if (phase == CreatorCodePhase.done)
            _card(
              _model.perk != null
                  ? _perkLines(_model.perk!, theme)
                  : [
                      Text(_model.perkPending
                          ? labels.perkPending
                          : labels.appliedNoCreator)
                    ],
              theme,
            )
          else if (alreadyApplied)
            _card(
              current.perk != null
                  ? _perkLines(current.perk!, theme)
                  : [Text(labels.currentReferralNoCreator)],
              theme,
            )
          else ...[
            if (widget.showsTitle) ...[
              Text(
                labels.title,
                style: theme.titleStyle?.copyWith(color: theme.textColor),
              ),
              const SizedBox(height: 16),
            ],
            if (_model.removed) ...[
              Text(labels.removedNotice,
                  style: TextStyle(color: theme.secondaryTextColor)),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _text,
              enabled: phase != CreatorCodePhase.applying,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              style: TextStyle(color: theme.textColor),
              cursorColor: theme.accent,
              decoration: InputDecoration(
                hintText: labels.placeholder,
                hintStyle: TextStyle(color: theme.secondaryTextColor),
                filled: true,
                fillColor: theme.fieldBackground,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                  borderSide: BorderSide(color: theme.fieldBorder!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                  borderSide: BorderSide(color: theme.accent!),
                ),
              ),
              onChanged: (text) => _model.code = text,
              onSubmitted: (_) {
                if (_model.isBusy) return;
                if (_model.phase == CreatorCodePhase.valid) {
                  unawaited(_model.apply());
                } else {
                  unawaited(_model.validatePreview());
                }
              },
            ),
            const SizedBox(height: 8),
            if (phase == CreatorCodePhase.valid) ...[
              if (_model.perk != null)
                Text(labels.perkPreview
                    .replaceAll('{perk}', _model.perk!.label)),
              _button(labels.useThisCode, () => _model.apply(), theme),
            ],
            if (_model.isBusy)
              _progress(
                  phase == CreatorCodePhase.applying
                      ? labels.applying
                      : labels.checking,
                  theme),
            if (_model.issue != null)
              Semantics(
                liveRegion: true,
                child: Text(labels.error(_model.issue!),
                    style: TextStyle(color: theme.errorTextColor)),
              ),
            if (_model.issue == CreatorCodeIssue.conflict)
              _button(labels.replace, () => _model.apply(confirmReplace: true),
                  theme),
            if (_model.issue == CreatorCodeIssue.network)
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: theme.secondaryTextColor),
                onPressed: () => unawaited(_model.retry()),
                child: Text(labels.retry),
              ),
            if (widget.onSkip != null)
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: theme.secondaryTextColor),
                onPressed: widget.onSkip,
                child: Text(labels.skip),
              ),
          ],
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback action, GoAlongTheme theme) =>
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: theme.accent,
          foregroundColor: theme.onAccent,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(theme.cornerRadius)),
        ),
        onPressed: action,
        child: Text(label),
      );

  List<Widget> _perkLines(Perk perk, GoAlongTheme theme) => [
        Text(widget.labels.perkGranted.replaceAll('{perk}', perk.label)),
        if (perk.expiresAt != null)
          Text(
            widget.labels.perkValidUntil.replaceAll(
                '{date}', widget.labels.formatDate(perk.expiresAt!)),
            style: TextStyle(color: theme.secondaryTextColor),
          ),
      ];

  Widget _card(List<Widget> children, GoAlongTheme theme) => Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardBackground,
            borderRadius: BorderRadius.circular(theme.cornerRadius + 4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      );

  Widget _progress(String label, GoAlongTheme theme) => Semantics(
        liveRegion: true,
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: theme.accent),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(label)),
          ],
        ),
      );
}
