# Python 基础编程

Python 是一种高级编程语言，以其简洁易读的语法而闻名。Python 支持多种编程范式，包括面向对象、函数式和过程式编程。

## English Summary

Python is a high-level language with readable syntax and multiple paradigms. This document covers basic types, control flow, functions, collections, and object-oriented programming.

## 日本語サマリー

Pythonは読みやすい文法を持つ高級言語で、複数のパラダイムに対応します。本ドキュメントは基本データ型、制御構文、関数、コレクション、オブジェクト指向を扱います。

## Resume Francais

Python est un langage de haut niveau a la syntaxe lisible et aux paradigmes multiples. Ce document presente les types de base, le controle de flux, les fonctions, les collections et la POO.


## 基本数据类型

- **整数 (int)**: 如 1, 2, 100, -5
- **浮点数 (float)**: 如 3.14, 2.718, -0.5
- **字符串 (str)**: 用引号括起来的文本，如 "Hello, World!"
- **布尔值 (bool)**: True 或 False

## 控制流程

Python 使用缩进来表示代码块，而不是使用花括号。

```python
if condition:
    statement
elif another_condition:
    statement
else:
    statement

for item in iterable:
    statement

while condition:
    statement
```

## 函数定义

```python
def greet(name):
    return f"Hello, {name}!"

result = greet("Python")
print(result)
```

## 列表和字典

列表是可变的有序集合：

```python
numbers = [1, 2, 3, 4, 5]
numbers.append(6)
```

字典是键值对的集合：

```python
person = {"name": "Alice", "age": 30}
person["city"] = "Beijing"
```

## 面向对象编程

Python 支持面向对象编程，可以定义类和对象：

```python
class Dog:
    def __init__(self, name, age):
        self.name = name
        self.age = age

    def bark(self):
        return f"{self.name} says Woof!"

dog = Dog("Buddy", 3)
print(dog.bark())
```

Python 的简洁性和强大的标准库使其成为数据科学、Web 开发、自动化脚本等领域的首选语言之一。

## English Summary

Python is a high-level language known for readable syntax and multiple paradigms. It covers core data types, control flow, functions, collections, and object-oriented programming.

## 日本語サマリー

Pythonは読みやすい文法と複数のパラダイムを持つ高水準言語です。基本的なデータ型、制御構文、関数、コレクション、オブジェクト指向を扱います。

## Resume en francais

Python est un langage de haut niveau avec une syntaxe lisible et plusieurs paradigmes. Le document presente les types de base, le flux de controle, les fonctions, les collections et la POO.

## English Summary

This document introduces Python fundamentals, including data types, control flow, functions, collections, and object-oriented programming.
It provides a concise tour of core syntax and common usage patterns.

## 日本語の要約

この文書は、Python の基礎（データ型、制御構文、関数、コレクション、オブジェクト指向）を紹介します。
基本的な文法と典型的な使い方を短くまとめています。

## Resume en francais

Ce document presente les bases de Python : types de donnees, controle de flux, fonctions, collections et programmation orientee objet.
Il offre un panorama concis de la syntaxe essentielle et des usages courants.


## English Summary

Python is a high-level language known for readable syntax and multiple paradigms. This document covers basic data types, control flow, functions, collections, and object-oriented programming.

## 日本語概要

Python は読みやすい構文を持つ高水準言語です。基本データ型、制御構文、関数、コレクション、オブジェクト指向を紹介します。

## Résumé en français

Python est un langage de haut niveau au style lisible. Ce document présente les types de base, le contrôle de flux, les fonctions, les collections et la POO.


## English Summary

Python is a high-level language known for readable syntax. This document covers data types, control flow, functions, lists, dictionaries, and classes.

## 日本語サマリー

Python は読みやすい高水準言語です。データ型、制御構文、関数、リスト、辞書、クラスの基本を紹介します。

## Résumé en français

Python est un langage de haut niveau avec une syntaxe claire. Ce document présente les types, le contrôle, les fonctions, les listes, les dictionnaires et les classes.

## English Summary

Python is a high-level language with clear syntax and multiple paradigms. It provides rich data types and straightforward object-oriented programming. These basics support scripting, web development, and data work.

## 日本語の概要

Pythonは読みやすい構文を持つ高水準言語です。基本データ型や制御構文、関数、クラスを理解すると、スクリプトやWeb開発に役立ちます。

## Resume en francais

Python est un langage de haut niveau avec une syntaxe lisible. Il prend en charge plusieurs paradigmes, les structures de donnees et la POO. Ces bases servent au script, au web et a la data.

## English Summary

Python is a high-level language with readable syntax. This summary covers data types, control flow, functions, lists, dictionaries, and OOP basics.

## 日本語概要

Pythonは読みやすい文法を持つ高水準言語です。基本的なデータ型、制御構文、関数、リスト・辞書、オブジェクト指向の概要を説明します。

## Résumé français

Python est un langage de haut niveau au style lisible. Ce résumé couvre les types de données, le flux de contrôle, les fonctions, les listes/dictionnaires et les bases de la POO.

## English Summary

Python is a high-level language known for its readable syntax. This document covers core data types, control flow, functions, lists/dictionaries, and basic OOP.

## 日本語サマリー

Pythonは読みやすい高水準言語で、基本データ型、制御構文、関数、リスト/辞書、OOPの概要を扱います。

## Résumé français

Python est un langage de haut niveau au style lisible. Ce document présente les types de base, le contrôle de flux, les fonctions, les listes/dictionnaires et la POO.

## English Summary

This document covers Python basics: data types, control flow, functions, lists/dictionaries, and object-oriented programming.

## 日本語サマリー

この文書は Python の基本（データ型、制御構文、関数、リスト/辞書、オブジェクト指向）をまとめています。

## Résumé français

Ce document présente les bases de Python : types de données, structures de contrôle, fonctions, listes/dictionnaires et POO.

## English Summary

Python is a high-level language known for readable syntax and multiple paradigms. It covers core data types, control flow, functions, lists/dictionaries, and object-oriented programming.

Key topics: data types, functions, lists, dictionaries, OOP.

## 日本語概要

Pythonは読みやすい文法を持つ高水準言語で、複数のパラダイムをサポートします。データ型、制御フロー、関数、リスト/辞書、オブジェクト指向を扱います。

主要トピック: データ型、関数、リスト、辞書、OOP。

## Résumé en français

Python est un langage de haut niveau avec une syntaxe lisible et plusieurs paradigmes. Ce document couvre les types de données, le contrôle de flux, les fonctions, les listes/dictionnaires et la POO.

Sujets clés : types de données, fonctions, listes, dictionnaires, POO.

## English Summary

Python is a high-level language known for readable syntax and rich libraries. It supports multiple paradigms, including object-oriented, functional, and procedural programming.

- Data types: integers, floats, strings, booleans
- Control flow: if/elif/else, for, while
- Functions and collections: lists and dictionaries
- OOP: classes, objects, and methods

## 日本語概要

Python は読みやすい構文と豊富な標準ライブラリを持つ高水準言語です。オブジェクト指向・関数型・手続き型をサポートします。

- データ型: 整数、浮動小数点、文字列、真偽値
- 制御構文: if/elif/else、for、while
- 関数とコレクション: リスト、辞書
- OOP: クラス、オブジェクト、メソッド

## Résumé en français

Python est un langage de haut niveau apprécié pour sa syntaxe lisible et ses bibliothèques riches. Il prend en charge plusieurs paradigmes, dont l’orienté objet, le fonctionnel et le procédural.

- Types de données : entiers, flottants, chaînes, booléens
- Flux de contrôle : if/elif/else, for, while
- Fonctions et collections : listes, dictionnaires
- POO : classes, objets, méthodes

