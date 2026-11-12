import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noodles/core/database/recipe_repository.dart';
import 'package:noodles/core/theme/app_theme.dart';
import 'package:noodles/features/recipes/presentation/new_recipe_page.dart';
import 'package:noodles/features/recipes/presentation/recipes_home_page.dart';
import 'package:noodles/models/inventory_settings.dart';
import 'package:noodles/models/recipe.dart';
import 'package:noodles/models/recipe_filter.dart';
import 'package:noodles/providers/inventory_providers.dart';
import 'package:noodles/providers/recipe_providers.dart';

Recipe recipe(
  String id,
  String title,
  String category,
  int day, {
  bool favorite = false,
}) => Recipe(
  id: id,
  title: title,
  category: category,
  description: '清爽家常风味',
  isFavorite: favorite,
  createdAt: DateTime(2026, 1, day),
  updatedAt: DateTime(2026, 2, 4 - day),
);

class RecipeStore implements RecipeRepository {
  final categories = ['面食', '汤羹'];
  final categoryOrders = <String, int>{};
  final items = [
    recipe('a', '番茄面', '面食', 1, favorite: true),
    recipe('b', '拌面', '面食', 2),
    recipe('c', '蔬菜汤', '汤羹', 3),
  ];
  Map<String, String>? created;
  Map<String, String>? updated;
  bool fail = false;
  @override
  Future<List<Recipe>> listRecipes() async => List.of(items);
  @override
  Future<List<String>> listRecipeCategories() async =>
      (await listRecipeCategoryOrders()).keys.toList();
  @override
  Future<Map<String, int>> listRecipeCategoryOrders() async {
    final sorted = List.of(categories)
      ..sort((a, b) {
        final result = (categoryOrders[a] ?? 0).compareTo(
          categoryOrders[b] ?? 0,
        );
        return result == 0
            ? categories.indexOf(a).compareTo(categories.indexOf(b))
            : result;
      });
    return {for (final name in sorted) name: categoryOrders[name] ?? 0};
  }

  @override
  Future<Recipe?> getRecipe(String id) async =>
      items.where((r) => r.id == id).firstOrNull;
  @override
  Future<void> saveRecipeCategory(
    String name, {
    String? previous,
    int? sortOrder,
  }) async {
    categoryOrders[name] = sortOrder ?? categoryOrders[previous] ?? 0;
    if (previous != null && previous != name) categoryOrders.remove(previous);
    if (previous == null) {
      categories.add(name);
      return;
    }
    categories[categories.indexOf(previous)] = name;
    for (var i = 0; i < items.length; i++) {
      if (items[i].category == previous) {
        items[i] = items[i].copyWith(category: name);
      }
    }
  }

  @override
  Future<List<RecipeVersion>> versions(String recipeId) async => [];
  @override
  Future<void> toggleFavorite(Recipe value) async {
    final index = items.indexWhere((r) => r.id == value.id);
    items[index] = value.copyWith(isFavorite: !value.isFavorite);
  }

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
    if (fail) throw StateError('offline');
    created = {
      'title': title,
      'category': category,
      'description': description,
      'ingredients': ingredientsText,
      'steps': stepsText,
    };
    return 'new';
  }

  @override
  Future<void> updateRecipe({
    required String id,
    required String title,
    required String category,
    required String description,
  }) async {
    updated = {
      'id': id,
      'title': title,
      'category': category,
      'description': description,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('ingredient amount is the text after the last whitespace', () {
    final items = parseRecipeIngredients('低筋 面粉   约100克\n盐 随便写\n糖');
    expect(items[0].name, '低筋 面粉');
    expect(items[0].amount, '约100克');
    expect(items[0].unit, isEmpty);
    expect(items[1].name, '盐');
    expect(items[1].amount, '随便写');
    expect(items[1].unit, isEmpty);
    expect(items[2].name, '糖');
    expect(items[2].amount, isEmpty);
  });

  test('recipe filters combine search, category and favorites without reordering source', () {
    final items = RecipeStore().items;
    expect(
      filterRecipes(
        items,
        keyword: ' 清爽 ',
        category: '面食',
        favoritesOnly: true,
      ).map((r) => r.id),
      ['a'],
    );
    expect(filterRecipes(items, category: '汤羹', favoritesOnly: true), isEmpty);
    expect(filterRecipes(items, sort: RecipeSort.created).map((r) => r.id), [
      'c',
      'b',
      'a',
    ]);
    expect(filterRecipes(items).map((r) => r.id), ['a', 'b', 'c']);
    expect(filterRecipes(items, keyword: '面食').length, 2);
    final english = [recipe('d', 'Pasta', 'Western', 1)];
    expect(
      filterRecipes([
        recipe('e', 'Soup', 'Western', 2),
        ...english,
      ], sort: RecipeSort.title).map((r) => r.id),
      ['d', 'e'],
    );
    expect(filterRecipes(english, keyword: 'PASTA').length, 1);
    expect(filterRecipes(english, keyword: ' western ').length, 1);
    expect(items.map((r) => r.id), ['a', 'b', 'c']);
  });

  Future<void> pump(WidgetTester tester, Widget page, RecipeStore store) async {
    tester.view.physicalSize = const Size(390, 844);
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
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => Navigator.push<Object?>(
                    context,
                    MaterialPageRoute(builder: (_) => page),
                  ),
                  child: const Text('打开页面'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开页面'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'recipe tab combines category and search without card favorite actions',
    (tester) async {
      final store = RecipeStore();
      await pump(tester, const RecipesHomePage(), store);
      expect(find.text('掌勺人'), findsOneWidget);
      expect(find.textContaining('仅看收藏'), findsNothing);
      expect(find.text('管理分类'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('菜谱分类设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('面食'));
      await tester.pumpAndSettle();
      expect(find.text('共 2 道菜谱'), findsOneWidget);
      expect(find.text('蔬菜汤'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '不存在');
      await tester.pumpAndSettle();
      expect(find.text('没有找到匹配的菜谱'), findsOneWidget);
      await tester.tap(find.byTooltip('清除筛选'));
      await tester.pumpAndSettle();
      expect(find.text('共 3 道菜谱'), findsOneWidget);
      expect(find.byTooltip('收藏'), findsNothing);
      expect(find.byTooltip('取消收藏'), findsNothing);
      await tester.tap(find.text('万物'));
      await tester.pumpAndSettle();
      expect(find.text('掌控万物'), findsOneWidget);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('个人设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile category opens recipe tab with selected category and clears search',
    (tester) async {
      final store = RecipeStore()..categories.add('烘焙');
      await pump(tester, const RecipesHomePage(), store);
      await tester.enterText(find.byType(TextField).first, '不存在');
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('菜谱分类设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('面食'));
      await tester.pumpAndSettle();
      expect(find.text('掌勺人'), findsOneWidget);
      expect(find.text('共 2 道菜谱'), findsOneWidget);
      expect(find.text('番茄面'), findsOneWidget);
      expect(find.text('拌面'), findsOneWidget);
      expect(find.text('蔬菜汤'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );

      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('菜谱分类设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('分类操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑分类'));
      await tester.pumpAndSettle();
      expect(find.text('编辑菜谱分类'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('烘焙'));
      await tester.pumpAndSettle();
      expect(find.text('掌勺人'), findsOneWidget);
      expect(find.text('没有找到匹配的菜谱'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'creation validates offscreen name and retains content after failure',
    (tester) async {
      final store = RecipeStore()..fail = true;
      await pump(tester, const NewRecipePage(), store);
      await tester.tap(find.widgetWithText(TextFormField, '菜谱分类'));
      await tester.pumpAndSettle();
      expect(find.text('选择分类'), findsOneWidget);
      await tester.tap(find.text('汤羹'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, '菜谱分类'))
            .initialValue,
        '汤羹',
      );
      await tester.tap(find.widgetWithText(TextFormField, '菜谱分类'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('未分类'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建菜谱'));
      await tester.pumpAndSettle();
      expect(find.text('请输入菜谱名称').hitTestable(), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, '菜谱名称 *'),
        ' 番茄面 ',
      );
      await tester.ensureVisible(find.widgetWithText(TextFormField, '食材与用量'));
      await tester.enterText(
        find.widgetWithText(TextFormField, '食材与用量'),
        '番茄 2 个',
      );
      await tester.ensureVisible(find.widgetWithText(TextFormField, '做法'));
      await tester.enterText(
        find.widgetWithText(TextFormField, '做法'),
        '煮面\n调味',
      );
      await tester.tap(find.text('创建菜谱'));
      await tester.pumpAndSettle();
      expect(find.text('保存失败，填写内容已保留，请重试'), findsOneWidget);
      store.fail = false;
      await tester.tap(find.text('创建菜谱'));
      await tester.pumpAndSettle();
      expect(store.created?['title'], '番茄面');
      expect(store.created?['category'], '未分类');
      expect(store.created?['ingredients'], '番茄 2 个');
      expect(store.created?['steps'], '煮面\n调味');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing recipe information uses existing identity without creating a version',
    (tester) async {
      final store = RecipeStore();
      await pump(tester, NewRecipePage(recipe: store.items.first), store);
      await tester.enterText(
        find.widgetWithText(TextFormField, '菜谱名称 *'),
        '番茄鸡蛋面',
      );
      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();
      expect(store.updated?['id'], 'a');
      expect(store.updated?['title'], '番茄鸡蛋面');
      expect(store.created, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category editing saves its order and keeps the renamed category on recipe save',
    (tester) async {
      final store = RecipeStore();
      await pump(tester, NewRecipePage(recipe: store.items.first), store);
      await tester.tap(find.widgetWithText(TextFormField, '菜谱分类'));
      await tester.pumpAndSettle();
      final categoryTile = find.ancestor(
        of: find.text('面食'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: categoryTile, matching: find.byTooltip('分类操作')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑分类'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, '分类名称'), '主食');
      await tester.enterText(find.widgetWithText(TextFormField, '排序'), '20');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.categoryOrders['主食'], 20);
      expect(
        tester.getTopLeft(find.text('汤羹')).dy,
        lessThan(tester.getTopLeft(find.text('主食')).dy),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();
      expect(store.updated?['category'], '主食');
      expect(tester.takeException(), isNull);
    },
  );
}
