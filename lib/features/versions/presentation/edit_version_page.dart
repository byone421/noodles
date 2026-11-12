import 'package:flutter/material.dart';

import '../../../models/recipe.dart';
import '../../recipes/presentation/new_recipe_page.dart';

class EditVersionPage extends StatelessWidget {
  const EditVersionPage({
    super.key,
    required this.recipeId,
    this.bundle,
    this.copyAsNew = false,
  });

  final String recipeId;
  final VersionBundle? bundle;
  final bool copyAsNew;

  @override
  Widget build(BuildContext context) =>
      NewRecipePage(recipeId: recipeId, bundle: bundle, copyAsNew: copyAsNew);
}
