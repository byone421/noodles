import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noodles/features/fanfou/presentation/fanfou_page.dart';
import 'package:noodles/features/recipes/presentation/recipe_detail_page.dart';
import 'package:noodles/features/recipes/presentation/recipes_home_page.dart';
import 'package:noodles/models/meal_draw.dart';

import 'recipe_navigation_detail_test.dart' show DetailStore, openPage;
import 'recipes_test.dart' show recipe;

const drawButton = ValueKey('draw-meal');

void main() {
  test(
    'draw keeps locks, prefers new recipes, never duplicates or changes input',
    () {
      final recipes = [
        for (var i = 0; i < 6; i++) recipe('$i', '菜$i', '家常菜', 1),
      ];
      for (var seed = 0; seed < 20; seed++) {
        final drawn = drawMeal(
          recipes,
          count: 3,
          previousIds: ['0', '1', '2'],
          lockedIds: {'1'},
          random: Random(seed),
        );
        final ids = drawn.map((recipe) => recipe.id).toSet();
        expect(ids, hasLength(3));
        expect(ids, contains('1'));
        expect(ids.intersection({'0', '2'}), isEmpty);
        expect(recipes.map((recipe) => recipe.id), [
          '0',
          '1',
          '2',
          '3',
          '4',
          '5',
        ]);
      }
      expect(drawMeal(recipes.take(2).toList(), count: 4), hasLength(2));
      expect(
        drawMeal([], count: 2, previousIds: ['0'], lockedIds: {'0'}),
        isEmpty,
      );
      expect(drawMeal(recipes, count: 0), isEmpty);
      final filled = drawMeal(
        recipes.take(3).toList(),
        count: 3,
        previousIds: ['missing', '1'],
        lockedIds: {'missing', '1'},
      );
      expect(filled.map((r) => r.id).toSet(), {'0', '1', '2'});
    },
  );

  testWidgets(
    'tab order, category/count, locks, detail, and tab state work together',
    (tester) async {
      final store = DetailStore();
      await openPage(tester, const RecipesHomePage(), store);
      final tabPositions = [
        for (final title in ['菜谱', '饭否', '万物', '我的'])
          tester.getCenter(find.text(title)).dx,
      ];
      expect(tabPositions, orderedEquals([...tabPositions]..sort()));
      await tester.tap(find.text('饭否'));
      await tester.pumpAndSettle();
      expect(find.text('今天吃点什么？'), findsOneWidget);
      expect(find.byTooltip('新建菜谱'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('choose-fanfou-categories')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('面食'));
      await tester.tap(find.text('完成选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(drawButton));
      await tester.pumpAndSettle();
      expect(find.text('番茄面'), findsOneWidget);
      expect(find.text('拌面'), findsOneWidget);
      expect(find.text('蔬菜汤'), findsNothing);
      await tester.tap(find.byTooltip('锁定番茄面'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(drawButton));
      await tester.pumpAndSettle();
      expect(find.byTooltip('解锁番茄面'), findsOneWidget);
      await tester.tap(find.text('万物'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('记录物品'), findsOneWidget);
      await tester.tap(find.text('饭否'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('解锁番茄面'), findsOneWidget);
      await tester.tap(find.text('番茄面'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetailPage), findsOneWidget);
      expect(
        tester.widget<RecipeDetailPage>(find.byType(RecipeDetailPage)).recipeId,
        'a',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multi-category draw fills only available recipes and all locks disable redraw',
    (tester) async {
      await openPage(tester, const RecipesHomePage(), DetailStore());
      await tester.tap(find.text('饭否'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('choose-fanfou-categories')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('面食'));
      await tester.tap(find.text('汤羹'));
      await tester.tap(find.text('完成选择'));
      await tester.tap(find.byTooltip('多一道'));
      await tester.tap(find.byTooltip('多一道'));
      await tester.pumpAndSettle();
      expect(find.text('只有 3 道可选，会全部端上桌。'), findsOneWidget);
      await tester.tap(find.byKey(drawButton));
      await tester.pumpAndSettle();
      expect(find.text('3 道菜'), findsOneWidget);
      for (final title in ['番茄面', '拌面', '蔬菜汤']) {
        await tester.ensureVisible(find.byTooltip('锁定$title'));
        await tester.tap(find.byTooltip('锁定$title'));
        await tester.pumpAndSettle();
      }
      expect(
        tester.widget<FilledButton>(find.byKey(drawButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('解锁蔬菜汤'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byKey(drawButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty category, empty library and narrow large-text layout have usable states',
    (tester) async {
      final store = DetailStore()..categories.add('烘焙');
      await openPage(
        tester,
        Scaffold(
          body: FanfouPage(onOpenRecipe: (_) {}, onAddRecipe: () {}),
        ),
        store,
        size: const Size(320, 740),
        textScale: 1.3,
      );
      await tester.tap(find.byKey(const ValueKey('choose-fanfou-categories')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('烘焙'));
      await tester.tap(find.text('完成选择'));
      await tester.pumpAndSettle();
      expect(find.text('这个分类还没有菜谱，换一类试试。'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(drawButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('choose-fanfou-categories')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.tap(find.text('完成选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(drawButton));
      await tester.pumpAndSettle();
      expect(find.text('2 道菜'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      var addTapped = false;
      await openPage(
        tester,
        Scaffold(
          body: FanfouPage(
            onOpenRecipe: (_) {},
            onAddRecipe: () {
              addTapped = true;
            },
          ),
        ),
        DetailStore()..items.clear(),
      );
      await tester.tap(find.text('去录入菜谱'));
      expect(addTapped, isTrue);
      expect(find.byKey(drawButton), findsNothing);
    },
  );

  testWidgets(
    'many categories are searchable on the picker, not expanded on Fanfou',
    (tester) async {
      final store = DetailStore()
        ..categories.addAll([for (var i = 0; i < 100; i++) '分类$i']);
      await openPage(tester, const RecipesHomePage(), store);
      await tester.tap(find.text('饭否'));
      await tester.pumpAndSettle();
      expect(find.text('分类99'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('choose-fanfou-categories')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '分类99');
      await tester.pumpAndSettle();
      expect(find.text('分类99'), findsOneWidget);
      await tester.tap(find.text('分类99'));
      await tester.tap(find.text('完成选择'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 个分类'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
