import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noodles/core/theme/app_theme.dart';
import 'package:noodles/features/recipes/presentation/new_recipe_page.dart';
import 'package:noodles/features/versions/presentation/edit_version_page.dart';
import 'package:noodles/models/recipe.dart';
import 'package:noodles/providers/recipe_providers.dart';

import 'recipe_navigation_detail_test.dart' show makeBundle;
import 'recipes_test.dart' show RecipeStore;

class PhotoStore extends RecipeStore {
  List<String>? savedImages;
  List<IngredientInput>? savedIngredients;
  List<String>? savedSteps;
  String? savedVersionId;

  @override
  Future<String> saveVersion({
    required String recipeId,
    String? versionId,
    required String title,
    required String note,
    double? rating,
    required List<IngredientInput> ingredients,
    required List<String> steps,
    String? imagePath,
    List<String>? imagePaths,
    String feedback = '',
    String improvement = '',
  }) async {
    savedImages = imagePaths;
    savedIngredients = ingredients;
    savedSteps = steps;
    savedVersionId = versionId;
    return versionId ?? 'copy';
  }
}

void main() {
  const picker = MethodChannel('plugins.flutter.io/image_picker');

  Future<void> open(WidgetTester tester, Widget page, PhotoStore store) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWith((_) async => store)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push<Object?>(
                  context,
                  MaterialPageRoute(builder: (_) => page),
                ),
                child: const Text('打开表单'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开表单'));
    await tester.pumpAndSettle();
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, null);
  });

  testWidgets(
    'creation supports camera, cancellation, errors and a hard five-photo cap',
    (tester) async {
      final calls = <MethodCall>[];
      var failCamera = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(picker, (call) async {
            calls.add(call);
            if (call.method == 'pickImage') {
              if (failCamera) {
                throw PlatformException(code: 'camera_access_denied');
              }
              return null;
            }
            return List.generate(7, (i) => 'photo$i.jpg');
          });
      await open(tester, const NewRecipePage(), PhotoStore());
      await tester.ensureVisible(find.text('拍照'));
      await tester.tap(find.text('拍照'));
      await tester.pumpAndSettle();
      expect(calls.last.arguments['source'], 0);
      expect(find.textContaining('0/5'), findsOneWidget);
      failCamera = true;
      await tester.tap(find.text('拍照'));
      await tester.pumpAndSettle();
      expect(find.text('无法拍照，请检查相机权限'), findsOneWidget);
      await tester.tap(find.text('选择图片'));
      await tester.pumpAndSettle();
      expect(calls.last.arguments['limit'], 5);
      expect(find.textContaining('5/5'), findsOneWidget);
      expect(find.byTooltip('移除第 5 张图片'), findsOneWidget);
      expect(find.byTooltip('移除第 6 张图片'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '拍照'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '选择图片'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byTooltip('移除第 1 张图片'));
      await tester.tap(find.byTooltip('移除第 1 张图片'));
      await tester.pumpAndSettle();
      expect(find.textContaining('4/5'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '选择图片'))
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.text('选择图片'));
      await tester.tap(find.text('选择图片'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'pickImage');
      expect(calls.last.arguments['source'], 1);
      expect(find.textContaining('4/5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final copy in [false, true]) {
    testWidgets(
      'version form matches creation and preserves all photos when copy=$copy',
      (tester) async {
        final store = PhotoStore();
        final original = makeBundle(1);
        final paths = List.generate(5, (i) => 'saved$i.jpg');
        final bundle = VersionBundle(
          version: original.version,
          ingredients: original.ingredients,
          steps: original.steps,
          finishedRecord: FinishedRecord(
            id: 'f',
            versionId: original.version.id,
            imagePaths: paths,
            note: '口感很好',
            nextImprovement: '少放盐',
            createdAt: DateTime(2026),
          ),
        );
        await open(
          tester,
          EditVersionPage(recipeId: 'a', bundle: bundle, copyAsNew: copy),
          store,
        );
        expect(find.text('准备食材'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, '食材与用量'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, '做法'), findsOneWidget);
        expect(find.textContaining('5/5'), findsOneWidget);
        final oldSteps = tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, '做法'))
            .controller!
            .text;
        expect(oldSteps, original.steps.single.content);
        await tester.tap(find.text('保存版本'));
        await tester.pumpAndSettle();
        expect(store.savedImages, paths);
        expect(store.savedVersionId, copy ? null : original.version.id);
        expect(store.savedIngredients!.single.name, '番茄');
        expect(store.savedIngredients!.single.amount, '2');
        expect(store.savedSteps, [original.steps.single.content]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
