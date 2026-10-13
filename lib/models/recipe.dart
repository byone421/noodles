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
  const FinishedRecord({required this.id, required this.versionId, this.imagePath, this.rating, required this.note, required this.nextImprovement, required this.createdAt});
  final String id;
  final String versionId;
  final String? imagePath;
  final double? rating;
  final String note;
  final String nextImprovement;
  final DateTime createdAt;
  factory FinishedRecord.fromMap(Map<String, Object?> m) => FinishedRecord(id: m['id']! as String, versionId: m['version_id']! as String, imagePath: m['image_path'] as String?, rating: (m['rating'] as num?)?.toDouble(), note: m['note'] as String? ?? '', nextImprovement: m['next_improvement'] as String? ?? '', createdAt: DateTime.parse(m['created_at']! as String));
  Map<String, Object?> toMap() => {'id': id, 'version_id': versionId, 'image_path': imagePath, 'rating': rating, 'note': note, 'next_improvement': nextImprovement, 'created_at': createdAt.toIso8601String()};
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
