import 'dart:convert';

import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart'
    hide QuoteBlockComponentBuilder, quoteNode, QuoteBlockKeys;
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:collection/collection.dart';
import 'package:string_validator/string_validator.dart';

class EditorMigration {
  // AppFlowy 0.1.x -> 0.2
  //
  // The cover node has been deprecated, and use page/attributes/cover instead.
  // cover node -> page/attributes/cover
  //
  // mark the textNode deprecated. use paragraph node instead.
  // text node -> paragraph node
  // delta -> attributes/delta
  //
  // mark the subtype deprecated. use type instead.
  // for example, text/checkbox -> checkbox_list
  //
  // some attribute keys.
  // ...
  static Document migrateDocument(String json) {
    final map = jsonDecode(json);
    assert(map['document'] != null);
    final documentV0 = Map<String, Object>.from(map['document'] as Map);
    final rootV0 = NodeV0.fromJson(documentV0);
    final root = migrateNode(rootV0);
    return Document(root: root);
  }

  static Node migrateNode(NodeV0 nodeV0) {
    Node? node;
    final children = nodeV0.children.map((e) => migrateNode(e)).toList();
    final id = nodeV0.id;
    if (id == 'editor') {
      final coverNode = children.firstWhereOrNull(
        (element) => element.id == 'cover',
      );
      if (coverNode != null) {
        node = pageNode(
          children: children,
          attributes: coverNode.attributes,
        );
      } else {
        node = pageNode(children: children);
      }
    } else if (id == 'callout') {
      final icon = nodeV0.attributes[CalloutBlockKeys.icon] ?? '📌';
      final iconType = nodeV0.attributes[CalloutBlockKeys.iconType] ??
          FlowyIconType.emoji.name;
      final delta =
          nodeV0.children.whereType<TextNodeV0>().fold(Delta(), (p, e) {
        final delta = migrateDelta(e.delta);
        final textInserts = delta.whereType<TextInsert>();
        for (final element in textInserts) {
          p.add(element);
        }
        return p..insert('\n');
      });
      EmojiIconData? emojiIconData;
      try {
        emojiIconData =
            EmojiIconData(FlowyIconType.values.byName(iconType), icon);
      } catch (e) {
        Log.error(
          'migrateNode get EmojiIconData error with :${nodeV0.attributes}',
          e,
        );
      }
      node = calloutNode(
        emoji: emojiIconData,
        delta: delta,
      );
    } else if (id == 'divider') {
      // divider -> divider
      node = dividerNode();
    } else if (id == 'math_equation') {
      // math_equation -> math_equation
      final formula = nodeV0.attributes['math_equation'] ?? '';
      node = mathEquationNode(formula: formula);
    } else if (nodeV0 is TextNodeV0) {
      final delta = migrateDelta(nodeV0.delta);
      final deltaJson = delta.toJson();
      final attributes = {'delta': deltaJson};
      if (id == 'text') {
        // text -> paragraph
        node = paragraphNode(
          attributes: attributes,
          children: children,
        );
      } else if (nodeV0.id == 'text/heading') {
        // text/heading -> heading
        final heading = nodeV0.attributes.heading?.replaceAll('h', '');
        final level = int.tryParse(heading ?? '') ?? 1;
        node = headingNode(
          level: level,
          attributes: attributes,
        );
      } else if (id == 'text/checkbox') {
        // text/checkbox -> todo_list
        final checked = nodeV0.attributes.check;
        node = todoListNode(
          checked: checked,
          attributes: attributes,
          children: children,
        );
      } else if (id == 'text/quote') {
        // text/quote -> quote
        node = quoteNode(attributes: attributes);
      } else if (id == 'text/number-list') {
        // text/number-list -> numbered_list
        node = numberedListNode(
          attributes: attributes,
          children: children,
        );
      } else if (id == 'text/bulleted-list') {
        // text/bulleted-list -> bulleted_list
        node = bulletedListNode(
          attributes: attributes,
          children: children,
        );
      } else if (id == 'text/code_block') {
        // text/code_block -> code
        final language = nodeV0.attributes['language'];
        node = codeBlockNode(delta: delta, language: language);
      }
    } else if (id == 'cover') {
      node = paragraphNode();
    }

    return node ?? paragraphNode(text: jsonEncode(nodeV0.toJson()));
  }

  // migrate the attributes.
  // backgroundColor -> highlightColor
  // color -> textColor
  static Delta migrateDelta(Delta delta) {
    final textInserts = delta
        .whereType<TextInsert>()
        .map(
          (e) => TextInsert(
            e.text,
            attributes: migrateAttributes(e.attributes),
          ),
        )
        .toList(growable: false);
    return Delta(operations: textInserts.toList());
  }

  static Attributes? migrateAttributes(Attributes? attributes) {
    if (attributes == null) {
      return null;
    }
    const backgroundColor = 'backgroundColor';
    if (attributes.containsKey(backgroundColor)) {
      attributes[AppFlowyRichTextKeys.backgroundColor] =
          attributes[backgroundColor];
      attributes.remove(backgroundColor);
    }
    const color = 'color';
    if (attributes.containsKey(color)) {
      attributes[AppFlowyRichTextKeys.textColor] = attributes[color];
      attributes.remove(color);
    }
    return attributes;
  }

  // Before version 0.5.5, the cover is stored in the document root.
  // Now, the cover is stored in the view.ext.
  static void migrateCoverIfNeeded(
    ViewPB view,
    Attributes attributes, {
    bool overwrite = false,
  }) async {
    if (view.extra.isNotEmpty && !overwrite) {
      return;
    }

    final coverType = CoverType.fromString(
      attributes[DocumentHeaderBlockKeys.coverType],
    );
    final coverDetails = attributes[DocumentHeaderBlockKeys.coverDetails];

    Map extra = {};

    if (coverType == CoverType.none ||
        coverDetails == null ||
        coverDetails is! String) {
      extra = {
        ViewExtKeys.coverKey: {
          ViewExtKeys.coverTypeKey: PageStyleCoverImageType.none.toString(),
          ViewExtKeys.coverValueKey: '',
        },
      };
    } else {
      switch (coverType) {
        case CoverType.asset:
          extra = {
            ViewExtKeys.coverKey: {
              ViewExtKeys.coverTypeKey:
                  PageStyleCoverImageType.builtInImage.toString(),
              ViewExtKeys.coverValueKey: coverDetails,
            },
          };
          break;
        case CoverType.color:
          extra = {
            ViewExtKeys.coverKey: {
              ViewExtKeys.coverTypeKey:
                  PageStyleCoverImageType.pureColor.toString(),
              ViewExtKeys.coverValueKey: coverDetails,
            },
          };
          break;
        case CoverType.file:
          if (isURL(coverDetails)) {
            if (coverDetails.contains('unsplash')) {
              extra = {
                ViewExtKeys.coverKey: {
                  ViewExtKeys.coverTypeKey:
                      PageStyleCoverImageType.unsplashImage.toString(),
                  ViewExtKeys.coverValueKey: coverDetails,
                },
              };
            } else {
              extra = {
                ViewExtKeys.coverKey: {
                  ViewExtKeys.coverTypeKey:
                      PageStyleCoverImageType.customImage.toString(),
                  ViewExtKeys.coverValueKey: coverDetails,
                },
              };
            }
          } else {
            extra = {
              ViewExtKeys.coverKey: {
                ViewExtKeys.coverTypeKey:
                    PageStyleCoverImageType.localImage.toString(),
                ViewExtKeys.coverValueKey: coverDetails,
              },
            };
          }
          break;
        default:
      }
    }

    if (extra.isEmpty) {
      return;
    }

    try {
      final current = view.extra.isNotEmpty ? jsonDecode(view.extra) : {};
      final merged = mergeMaps(current, extra);
      await ViewBackendService.updateView(
        viewId: view.id,
        extra: jsonEncode(merged),
      );
    } catch (e) {
      Log.error('Failed to migrating cover: $e');
    }
  }
}
