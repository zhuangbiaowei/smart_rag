# Python Programming Basics

Python is a high-level programming language known for clean, readable syntax. It supports multiple paradigms, including object-oriented, functional, and procedural programming.

## Basic Data Types

- **Integers (int)**: 1, 2, 100, -5
- **Floats (float)**: 3.14, 2.718, -0.5
- **Strings (str)**: Text wrapped in quotes, like "Hello, World!"
- **Booleans (bool)**: True or False

## Control Flow

Python uses indentation to define code blocks instead of braces.

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

## Functions

```python
def greet(name):
    return f"Hello, {name}!"

result = greet("Python")
print(result)
```

## Lists and Dictionaries

Lists are ordered and mutable:

```python
numbers = [1, 2, 3, 4, 5]
numbers.append(6)
```

Dictionaries store key-value pairs:

```python
person = {"name": "Alice", "age": 30}
person["city"] = "Beijing"
```

## Object-Oriented Programming

Python supports classes and objects:

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

Python's simplicity and strong standard library make it a top choice for data science, web development, and automation.
