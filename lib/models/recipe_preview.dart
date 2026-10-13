import 'package:flutter/material.dart';

class RecipePreview {
  const RecipePreview({
    required this.title,
    required this.category,
    required this.meta,
    required this.rating,
    required this.icon,
    required this.color,
  });

  final String title;
  final String category;
  final String meta;
  final double rating;
  final IconData icon;
  final Color color;
}

const demoRecipes = [
  RecipePreview(
    title: '番茄牛腩',
    category: '家常菜',
    meta: '3 个版本 · 2 小时前',
    rating: 4.8,
    icon: Icons.restaurant,
    color: Color(0xFFD98253),
  ),
  RecipePreview(
    title: '蒜香黄油虾',
    category: '快手菜',
    meta: '2 个版本 · 昨天',
    rating: 4.3,
    icon: Icons.set_meal,
    color: Color(0xFFD1A44E),
  ),
  RecipePreview(
    title: '葱油拌面',
    category: '面食',
    meta: '4 个版本 · 3 天前',
    rating: 4.9,
    icon: Icons.ramen_dining,
    color: Color(0xFF7995AA),
  ),
];
