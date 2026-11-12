import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noodles/core/theme/app_theme.dart';
import 'package:noodles/features/recipes/presentation/new_recipe_page.dart';
import 'package:noodles/features/recipes/presentation/recipe_detail_page.dart';
import 'package:noodles/features/recipes/presentation/recipes_home_page.dart';
import 'package:noodles/features/versions/presentation/edit_version_page.dart';
import 'package:noodles/models/inventory_settings.dart';
import 'package:noodles/models/recipe.dart';
import 'package:noodles/providers/inventory_providers.dart';
import 'package:noodles/providers/recipe_providers.dart';

import 'recipes_test.dart' show RecipeStore;

class DetailStore extends RecipeStore {
  final bundles = <String, VersionBundle>{};

  @override
  Future<String> createRecipe({
    required String title,
    required String category,
    String description = '',
    String ingredientsText = '',
    String stepsText = '',
    List<String> imagePaths = const [],
    double? rating,
    String feedback = '',
    String improvement = '',
  }) async {
    final id = await super.createRecipe(
      title: title,
      category: category,
      description: description,
      ingredientsText: ingredientsText,
      stepsText: stepsText,
      imagePaths: imagePaths,
      rating: rating,
      feedback: feedback,
      improvement: improvement,
    );
    items.insert(
      0,
      Recipe(
        id: id,
        title: title,
        category: category,
        description: description,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    return id;
  }

  @override
  Future<List<RecipeVersion>> versions(String recipeId) async => bundles.values
      .map((bundle) => bundle.version)
      .where((version) => version.recipeId == recipeId)
      .toList();

  @override
  Future<VersionBundle?> bundle(String versionId) async => bundles[versionId];
}

VersionBundle makeBundle(int number) => VersionBundle(
  version: RecipeVersion(
    id: 'v$number',
    recipeId: 'a',
    versionNumber: number,
    title: number == 2 ? '少盐改良版' : '最初的做法',
    note: '记录每次调整的味道',
    rating: number == 2 ? 4.5 : null,
    isBest: number == 2,
    createdAt: DateTime(2026, 11, 12),
    updatedAt: DateTime(2026, 11, 12),
  ),
  ingredients: [
    Ingredient(
      id: 'i$number',
      versionId: 'v$number',
      name: '番茄',
      amount: '2',
      unit: '个',
      sortOrder: 0,
    ),
  ],
  steps: [
    CookingStep(
      id: 's$number',
      versionId: 'v$number',
      content: number == 2 ? '番茄切块后炒出汁，加入清水煮开，再放入面条煮熟，最后少量加盐调味。' : '先煮面，再加入番茄。',
      sortOrder: 0,
    ),
  ],
);

Future<void> openPage(
  WidgetTester tester,
  Widget page,
  DetailStore store, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWith((_) async => store),
        statsProvider.overrideWith((_) async => {}),
        inventoryItemsProvider.overrideWith((_) async => []),
        inventoryCategoriesProvider.overrideWith((_) async => []),
        expirySettingsProvider.overrideWith(
          (_) async => const ExpirySettings(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'creating from a filtered recipe tab returns to the updated list',
    (tester) async {
      final store = DetailStore();
      await openPage(tester, const RecipesHomePage(), store);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('菜谱分类设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('面食'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '番茄');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('新建菜谱'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '菜谱名称 *'),
        '新菜谱',
      );
      await tester.tap(find.text('创建菜谱'));
      await tester.pumpAndSettle();
      expect(find.byType(NewRecipePage), findsNothing);
      expect(find.byType(RecipeDetailPage), findsNothing);
      expect(find.text('掌勺人'), findsOneWidget);
      expect(find.text('新菜谱'), findsOneWidget);
      expect(find.text('共 4 道菜谱'), findsOneWidget);
      expect(find.text('菜谱已创建'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'detail switches versions and edits the selected version on a narrow screen',
    (tester) async {
      final store = DetailStore();
      for (final number in [2, 1]) {
        final bundle = makeBundle(number);
        store.bundles[bundle.version.id] = bundle;
      }
      await openPage(
        tester,
        const RecipeDetailPage(recipeId: 'a'),
        store,
        size: const Size(320, 740),
        textScale: 1.3,
      );
      expect(find.text('少盐改良版'), findsOneWidget);
      expect(find.text('评分 4.5 分'), findsOneWidget);
      expect(find.text('编辑当前版本').hitTestable(), findsOneWidget);
      await tester.tap(find.text('版本 1'));
      await tester.pumpAndSettle();
      expect(find.text('最初的做法'), findsOneWidget);
      expect(find.text('尚未评分'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('制作步骤'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('先煮面，再加入番茄。'), findsOneWidget);
      expect(find.text('编辑当前版本').hitTestable(), findsOneWidget);
      await tester.tap(find.text('编辑当前版本'));
      await tester.pumpAndSettle();
      final editor = tester.widget<EditVersionPage>(
        find.byType(EditVersionPage),
      );
      expect(editor.bundle?.version.id, 'v1');
      expect(editor.copyAsNew, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('detail without versions offers the first version action', (
    tester,
  ) async {
    await openPage(
      tester,
      const RecipeDetailPage(recipeId: 'a'),
      DetailStore(),
    );
    expect(find.text('还没有烹饪版本'), findsOneWidget);
    await tester.tap(find.text('创建第一个版本'));
    await tester.pumpAndSettle();
    final editor = tester.widget<EditVersionPage>(find.byType(EditVersionPage));
    expect(editor.recipeId, 'a');
    expect(editor.bundle, isNull);
    expect(tester.takeException(), isNull);
  });
}
