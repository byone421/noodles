import 'recipe.dart';

enum RecipeSort {
  updated('最近更新'),
  created('最近创建'),
  title('名称排序');

  const RecipeSort(this.label);
  final String label;
}

List<Recipe> filterRecipes(
  List<Recipe> recipes, {
  String keyword = '',
  String? category,
  bool favoritesOnly = false,
  RecipeSort sort = RecipeSort.updated,
}) {
  final query = keyword.trim().toLowerCase();
  final result = recipes
      .where(
        (recipe) =>
            (category == null || recipe.category == category) &&
            (!favoritesOnly || recipe.isFavorite) &&
            [
              recipe.title,
              recipe.description,
              recipe.category,
            ].any((value) => value.toLowerCase().contains(query)),
      )
      .toList();
  result.sort((a, b) {
    final comparison = switch (sort) {
      RecipeSort.updated => b.updatedAt.compareTo(a.updatedAt),
      RecipeSort.created => b.createdAt.compareTo(a.createdAt),
      RecipeSort.title => a.title.compareTo(b.title),
    };
    return comparison == 0 ? a.id.compareTo(b.id) : comparison;
  });
  return result;
}
