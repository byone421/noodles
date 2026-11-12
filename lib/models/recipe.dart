import 'dart:convert';

const maxRecipeImages = 5;

class Recipe {
  const Recipe({required this.id, required this.title, required this.category, required this.description, this.coverImagePath, this.isFavorite = false, required this.createdAt, required this.updatedAt});
  final String id;
  final String title;
  final String category;
  final String description;
  final String? coverImagePath;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Recipe.fromMap(Map<String, Object?> map) => Recipe(id: map['id']! as String, title: map['title']! as String, category: map['category']! as String, description: map['description'] as String? ?? '', coverImagePath: map['cover_image_path'] as String?, isFavorite: (map['is_favorite'] as int? ?? 0) == 1, createdAt: DateTime.parse(map['created_at']! as String), updatedAt: DateTime.parse(map['updated_at']! as String));
  Map<String, Object?> toMap() => {'id': id, 'title': title, 'category': category, 'description': description, 'cover_image_path': coverImagePath, 'is_favorite': isFavorite ? 1 : 0, 'created_at': createdAt.toIso8601String(), 'updated_at': updatedAt.toIso8601String()};
  Recipe copyWith({String? title, String? category, String? description, String? coverImagePath, bool? isFavorite}) => Recipe(id: id, title: title ?? this.title, category: category ?? this.category, description: description ?? this.description, coverImagePath: coverImagePath ?? this.coverImagePath, isFavorite: isFavorite ?? this.isFavorite, createdAt: createdAt, updatedAt: DateTime.now());
}

class RecipeVersion {
  const RecipeVersion({required this.id, required this.recipeId, required this.versionNumber, required this.title, required this.note, this.rating, this.isBest = false, required this.createdAt, required this.updatedAt});
  final String id;
  final String recipeId;
  final int versionNumber;
  final String title;
  final String note;
  final double? rating;
  final bool isBest;
  final DateTime createdAt;
  final DateTime updatedAt;
  factory RecipeVersion.fromMap(Map<String, Object?> m) => RecipeVersion(id: m['id']! as String, recipeId: m['recipe_id']! as String, versionNumber: m['version_number']! as int, title: m['title'] as String? ?? '', note: m['note'] as String? ?? '', rating: (m['rating'] as num?)?.toDouble(), isBest: (m['is_best'] as int? ?? 0) == 1, createdAt: DateTime.parse(m['created_at']! as String), updatedAt: DateTime.parse(m['updated_at']! as String));
  Map<String, Object?> toMap() => {'id': id, 'recipe_id': recipeId, 'version_number': versionNumber, 'title': title, 'note': note, 'rating': rating, 'is_best': isBest ? 1 : 0, 'created_at': createdAt.toIso8601String(), 'updated_at': updatedAt.toIso8601String()};
}

class Ingredient {
  const Ingredient({required this.id, required this.versionId, required this.name, required this.amount, required this.unit, required this.sortOrder});
  final String id;
  final String versionId;
  final String name;
  final String amount;
  final String unit;
  final int sortOrder;
  factory Ingredient.fromMap(Map<String, Object?> m) => Ingredient(id: m['id']! as String, versionId: m['version_id']! as String, name: m['name']! as String, amount: m['amount'] as String? ?? '', unit: m['unit'] as String? ?? '', sortOrder: m['sort_order']! as int);
  Map<String, Object?> toMap() => {'id': id, 'version_id': versionId, 'name': name, 'amount': amount, 'unit': unit, 'sort_order': sortOrder};
}

class CookingStep {
  const CookingStep({required this.id, required this.versionId, required this.content, required this.sortOrder});
  final String id;
  final String versionId;
  final String content;
  final int sortOrder;
  factory CookingStep.fromMap(Map<String, Object?> m) => CookingStep(id: m['id']! as String, versionId: m['version_id']! as String, content: m['content']! as String, sortOrder: m['sort_order']! as int);
  Map<String, Object?> toMap() => {'id': id, 'version_id': versionId, 'content': content, 'sort_order': sortOrder};
}

class FinishedRecord {
  FinishedRecord({
    required this.id,
    required this.versionId,
    String? imagePath,
    List<String> imagePaths = const [],
    this.rating,
    required this.note,
    required this.nextImprovement,
    required this.createdAt,
  }) : imagePaths = List.unmodifiable(imagePaths.isNotEmpty
          ? imagePaths
          : [if (imagePath != null && imagePath.isNotEmpty) imagePath]);
  final String id;
  final String versionId;
  final List<String> imagePaths;
  String? get imagePath => imagePaths.firstOrNull;

  static List<String> readImagePaths(Map<String, Object?> map) {
    final paths = (jsonDecode(map['image_paths'] as String? ?? '[]') as List)
        .cast<String>();
    return paths.isNotEmpty
        ? paths
        : [
            if (map['image_path'] case final String path when path.isNotEmpty)
              path,
          ];
  }

  final double? rating;
  final String note;
  final String nextImprovement;
  final DateTime createdAt;
  factory FinishedRecord.fromMap(Map<String, Object?> m) => FinishedRecord(
    id: m['id']! as String,
    versionId: m['version_id']! as String,
    imagePath: m['image_path'] as String?,
    imagePaths: readImagePaths(m),
    rating: (m['rating'] as num?)?.toDouble(),
    note: m['note'] as String? ?? '',
    nextImprovement: m['next_improvement'] as String? ?? '',
    createdAt: DateTime.parse(m['created_at']! as String),
  );
  Map<String, Object?> toMap() => {
    'id': id,
    'version_id': versionId,
    'image_path': imagePaths.firstOrNull,
    'image_paths': jsonEncode(imagePaths),
    'rating': rating,
    'note': note,
    'next_improvement': nextImprovement,
    'created_at': createdAt.toIso8601String(),
  };
}

class VersionBundle {
  const VersionBundle({required this.version, required this.ingredients, required this.steps, this.finishedRecord});
  final RecipeVersion version;
  final List<Ingredient> ingredients;
  final List<CookingStep> steps;
  final FinishedRecord? finishedRecord;
}

class IngredientInput {
  const IngredientInput({required this.name, required this.amount, required this.unit});
  final String name;
  final String amount;
  final String unit;
}
String formatRecipeIngredient(Ingredient item) => [
  item.name,
  item.amount,
  item.unit,
].where((part) => part.isNotEmpty).join(' ');

List<IngredientInput> parseRecipeIngredients(
  String text, {
  List<Ingredient> existing = const [],
}) => text
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .map((line) {
      final original = existing
          .where((item) => formatRecipeIngredient(item) == line)
          .firstOrNull;
      if (original != null) {
        return IngredientInput(
          name: original.name,
          amount: original.amount,
          unit: original.unit,
        );
      }
      final separator = line.lastIndexOf(RegExp(r'\s'));
      return IngredientInput(
        name: separator < 0 ? line : line.substring(0, separator).trim(),
        amount: separator < 0 ? '' : line.substring(separator + 1).trim(),
        unit: '',
      );
    })
    .toList();

List<String> parseRecipeSteps(
  String text, {
  List<String> existing = const [],
}) => text == existing.join('\n') ? List.of(existing) : text
    .split('\n')
    .map(
      (line) => existing.contains(line.trim())
          ? line.trim()
          : line.replaceFirst(RegExp(r'^\s*\d+[.)、]\s*'), '').trim(),
    )
    .where((line) => line.isNotEmpty)
    .toList();
