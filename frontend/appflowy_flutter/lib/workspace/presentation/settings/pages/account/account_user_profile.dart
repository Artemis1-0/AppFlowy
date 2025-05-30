import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/workspace/application/user/settings_user_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_input_field.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../shared/icon_emoji_picker/tab.dart';

// Account name and account avatar
class AccountUserProfile extends StatefulWidget {
  const AccountUserProfile({
    super.key,
    required this.name,
    required this.iconUrl,
    this.onSave,
  });

  final String name;
  final String iconUrl;
  final void Function(String)? onSave;

  @override
  State<AccountUserProfile> createState() => _AccountUserProfileState();
}

class _AccountUserProfileState extends State<AccountUserProfile> {
  late final TextEditingController nameController =
      TextEditingController(text: widget.name);
  final FocusNode focusNode = FocusNode();
  bool isEditing = false;
  bool isHovering = false;

  @override
  void initState() {
    super.initState();

    focusNode
      ..addListener(_handleFocusChange)
      ..onKeyEvent = _handleKeyEvent;
  }

  @override
  void dispose() {
    nameController.dispose();
    focusNode.removeListener(_handleFocusChange);
    focusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAvatar(),
        const HSpace(16),
        Flexible(
          child: isEditing ? _buildEditingField() : _buildNameDisplay(),
        ),
      ],
    );
  }

  Widget _buildAvatar() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showIconPickerDialog(context),
      child: FlowyHover(
        resetHoverOnRebuild: false,
        onHover: (state) => setState(() => isHovering = state),
        style: HoverStyle(
          hoverColor: Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: FlowyTooltip(
          message:
              LocaleKeys.settings_accountPage_general_changeProfilePicture.tr(),
          verticalOffset: 28,
          child: AFAvatar(
            url: widget.iconUrl,
            name: widget.name,
            size: AFAvatarSize.l,
          ),
        ),
      ),
    );
  }

  Widget _buildNameDisplay() {
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              widget.name,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.primary,
              ),
            ),
          ),
          const HSpace(4),
          AFGhostButton.normal(
            size: AFButtonSize.s,
            padding: EdgeInsets.all(theme.spacing.xs),
            onTap: () => setState(() => isEditing = true),
            builder: (context, isHovering, disabled) => FlowySvg(
              FlowySvgs.toolbar_link_edit_m,
              size: const Size.square(20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditingField() {
    return SettingsInputField(
      textController: nameController,
      value: widget.name,
      focusNode: focusNode..requestFocus(),
      onCancel: () => setState(() => isEditing = false),
      onSave: (_) => _saveChanges(),
    );
  }

  Future<void> _showIconPickerDialog(BuildContext context) {
    return showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        children: [
          Container(
            height: 380,
            width: 360,
            margin: const EdgeInsets.all(0),
            child: FlowyIconEmojiPicker(
              tabs: const [PickerTabType.emoji],
              onSelectedEmoji: (r) {
                context
                    .read<SettingsUserViewBloc>()
                    .add(SettingsUserEvent.updateUserIcon(iconUrl: r.emoji));
                Navigator.of(dialogContext).pop();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleFocusChange() {
    if (!focusNode.hasFocus && isEditing && mounted) {
      _saveChanges();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        isEditing &&
        mounted) {
      setState(() => isEditing = false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _saveChanges() {
    widget.onSave?.call(nameController.text);
    setState(() => isEditing = false);
  }
}
