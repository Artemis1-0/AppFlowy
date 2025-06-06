import 'package:appflowy/features/share_tab/data/repositories/rust_share_with_user_repository.dart';
import 'package:appflowy/features/share_tab/logic/share_with_user_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/tab_bar_bloc.dart';
import 'package:appflowy/plugins/shared/share/_shared.dart';
import 'package:appflowy/plugins/shared/share/share_bloc.dart';
import 'package:appflowy/plugins/shared/share/share_menu.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/user/user_workspace_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ShareButton extends StatelessWidget {
  const ShareButton({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    final workspaceId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId ??
            '';
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) =>
              getIt<ShareBloc>(param1: view)..add(const ShareEvent.initial()),
        ),
        if (view.layout.isDatabaseView)
          BlocProvider(
            create: (context) => DatabaseTabBarBloc(
              view: view,
              compactModeId: view.id,
              enableCompactMode: false,
            )..add(const DatabaseTabBarEvent.initial()),
          ),
        BlocProvider(
          create: (context) => ShareWithUserBloc(
            repository: RustShareWithUserRepository(),
            pageId: view.id,
            workspaceId: workspaceId,
          )..add(const ShareWithUserEvent.init()),
        ),
      ],
      child: BlocListener<ShareBloc, ShareState>(
        listener: (context, state) {
          if (!state.isLoading && state.exportResult != null) {
            state.exportResult!.fold(
              (data) => _handleExportSuccess(context, data),
              (error) => _handleExportError(context, error),
            );
          }
        },
        child: BlocBuilder<ShareBloc, ShareState>(
          builder: (context, state) {
            final tabs = [
              if (state.enablePublish) ...[
                // share the same permission with publish
                ShareMenuTab.share,
                ShareMenuTab.publish,
              ],
              ShareMenuTab.exportAs,
            ];

            return ShareMenuButton(tabs: tabs);
          },
        ),
      ),
    );
  }

  void _handleExportSuccess(BuildContext context, ShareType shareType) {
    switch (shareType) {
      case ShareType.markdown:
      case ShareType.html:
      case ShareType.csv:
        showToastNotification(
          message: LocaleKeys.settings_files_exportFileSuccess.tr(),
        );
        break;
      default:
        break;
    }
  }

  void _handleExportError(BuildContext context, FlowyError error) {
    showToastNotification(
      message:
          '${LocaleKeys.settings_files_exportFileFail.tr()}: ${error.code}',
    );
  }
}
