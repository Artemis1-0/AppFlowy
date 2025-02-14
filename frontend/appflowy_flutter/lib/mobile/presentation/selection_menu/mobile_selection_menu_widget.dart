import 'dart:math';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'mobile_selection_menu_item.dart';
import 'mobile_selection_menu_item_widget.dart';

class MobileSelectionMenuWidget extends StatefulWidget {
  const MobileSelectionMenuWidget({
    super.key,
    required this.items,
    required this.itemCountFilter,
    required this.maxItemInRow,
    required this.menuService,
    required this.editorState,
    required this.onExit,
    required this.selectionMenuStyle,
    required this.deleteSlashByDefault,
    required this.singleColumn,
    required this.startOffset,
    this.nameBuilder,
  });

  final List<SelectionMenuItem> items;
  final int itemCountFilter;
  final int maxItemInRow;

  final SelectionMenuService menuService;
  final EditorState editorState;

  final VoidCallback onExit;

  final SelectionMenuStyle selectionMenuStyle;

  final bool deleteSlashByDefault;
  final bool singleColumn;
  final int startOffset;

  final SelectionMenuItemNameBuilder? nameBuilder;

  @override
  State<MobileSelectionMenuWidget> createState() =>
      _MobileSelectionMenuWidgetState();
}

class _MobileSelectionMenuWidgetState extends State<MobileSelectionMenuWidget> {
  final _focusNode = FocusNode(debugLabel: 'popup_list_widget');

  List<SelectionMenuItem> _showingItems = [];

  int _searchCounter = 0;

  EditorState get editorState => widget.editorState;

  SelectionMenuService get menuService => widget.menuService;

  String _keyword = '';

  String get keyword => _keyword;

  int selectedIndex = 0;

  List<SelectionMenuItem> get filterItems {
    final List<SelectionMenuItem> items = [];
    for (final item in widget.items) {
      if (item is MobileSelectionMenuItem) {
        for (final childItem in item.children) {
          items.add(childItem);
        }
      } else {
        items.add(item);
      }
    }
    return items;
  }

  set keyword(String newKeyword) {
    _keyword = newKeyword;

    // Search items according to the keyword, and calculate the length of
    //  the longest keyword, which is used to dismiss the selection_service.
    var maxKeywordLength = 0;

    final items = newKeyword.isEmpty
        ? widget.items
        : filterItems
            .where(
              (item) => item.allKeywords.any((keyword) {
                final value = keyword.contains(newKeyword.toLowerCase());
                if (value) {
                  maxKeywordLength = max(maxKeywordLength, keyword.length);
                }
                return value;
              }),
            )
            .toList(growable: false);

    AppFlowyEditorLog.ui.debug('$items');

    if (keyword.length >= maxKeywordLength + 2 &&
        !(widget.deleteSlashByDefault && _searchCounter < 2)) {
      return widget.onExit();
    }
    setState(() {
      selectedIndex = 0;
      _showingItems = items;
    });

    if (_showingItems.isEmpty) {
      _searchCounter++;
    } else {
      _searchCounter = 0;
    }
  }

  @override
  void initState() {
    super.initState();

    final List<SelectionMenuItem> items = [];
    for (final item in widget.items) {
      if (item is MobileSelectionMenuItem) {
        item.onSelected = () {
          if (mounted) {
            setState(() {
              _showingItems = item.children
                  .map((e) => e..onSelected = widget.onExit)
                  .toList();
            });
          }
        };
      }
      items.add(item);
    }
    _showingItems = items;

    keepEditorFocusNotifier.increase();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    editorState.selectionNotifier.addListener(onSelectionChanged);
  }

  @override
  void dispose() {
    editorState.selectionNotifier.removeListener(onSelectionChanged);
    _focusNode.dispose();
    keepEditorFocusNotifier.decrease();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.selectionMenuStyle.selectionMenuBackgroundColor,
          boxShadow: [
            BoxShadow(
              blurRadius: 5,
              spreadRadius: 1,
              color: Colors.black.withValues(alpha: 0.1),
            ),
          ],
          borderRadius: BorderRadius.circular(6.0),
        ),
        child: _showingItems.isEmpty
            ? _buildNoResultsWidget(context)
            : _buildResultsWidget(
                context,
                _showingItems,
                widget.itemCountFilter,
              ),
      ),
    );
  }

  void onSelectionChanged() {
    final selection = editorState.selection;
    if (selection == null) {
      widget.onExit();
      return;
    }
    if (!selection.isCollapsed) {
      widget.onExit();
      return;
    }
    final startOffset = widget.startOffset;
    final endOffset = selection.end.offset;
    if (endOffset < startOffset) {
      widget.onExit();
      return;
    }
    final node = editorState.getNodeAtPath(selection.start.path);
    final text = node?.delta?.toPlainText() ?? '';
    final search = text.substring(startOffset, endOffset);
    keyword = search;
  }

  Widget _buildResultsWidget(
    BuildContext buildContext,
    List<SelectionMenuItem> items,
    int itemCountFilter,
  ) {
    if (widget.singleColumn) {
      final List<Widget> itemWidgets = [];
      for (var i = 0; i < items.length; i++) {
        itemWidgets.add(
          GestureDetector(
            onTapDown: (e) {
              setState(() {
                selectedIndex = i;
              });
            },
            child: MobileSelectionMenuItemWidget(
              item: items[i],
              isSelected: i == selectedIndex,
              editorState: editorState,
              menuService: menuService,
              selectionMenuStyle: widget.selectionMenuStyle,
            ),
          ),
        );
      }
      return ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: 192,
          minWidth: 240,
          maxWidth: 240,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: itemWidgets,
        ),
      );
    } else {
      final List<Widget> columns = [];
      List<Widget> itemWidgets = [];
      // apply item count filter
      if (itemCountFilter > 0) {
        items = items.take(itemCountFilter).toList();
      }

      for (var i = 0; i < items.length; i++) {
        if (i != 0 && i % (widget.maxItemInRow) == 0) {
          columns.add(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: itemWidgets,
            ),
          );
          itemWidgets = [];
        }
        itemWidgets.add(
          MobileSelectionMenuItemWidget(
            item: items[i],
            isSelected: false,
            editorState: editorState,
            menuService: menuService,
            selectionMenuStyle: widget.selectionMenuStyle,
          ),
        );
      }
      if (itemWidgets.isNotEmpty) {
        columns.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: itemWidgets,
          ),
        );
        itemWidgets = [];
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: columns,
      );
    }
  }

  Widget _buildNoResultsWidget(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(8.0),
      child: SizedBox(
        width: 140,
        child: Material(
          child: Text(
            "No results",
            style: TextStyle(fontSize: 18.0, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
