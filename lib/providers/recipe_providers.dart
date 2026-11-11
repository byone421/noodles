import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/recipe_repository.dart';
import '../models/recipe.dart';

final repositoryProvider = FutureProvider<RecipeRepository>((ref) async => RecipeRepository.open());
final recipesProvider = FutureProvider<List<Recipe>>((ref) async => (await ref.watch(repositoryProvider.future)).listRecipes());
final recipeProvider = FutureProvider.family<Recipe?, String>((ref, id) async => (await ref.watch(repositoryProvider.future)).getRecipe(id));
final versionsProvider = FutureProvider.family<List<RecipeVersion>, String>((ref, id) async => (await ref.watch(repositoryProvider.future)).versions(id));
final bundleProvider = FutureProvider.family<VersionBundle?, String>((ref, id) async => (await ref.watch(repositoryProvider.future)).bundle(id));
final statsProvider = FutureProvider<Map<String, int>>((ref) async => (await ref.watch(repositoryProvider.future)).stats());
final recipeCategoriesProvider = FutureProvider<List<String>>((ref) async => (await ref.watch(repositoryProvider.future)).listRecipeCategories());
