# Python 基础编程

Python 是一种高级编程语言，以其简洁易读的语法而闻名。Python 支持多种编程范式，包括面向对象、函数式和过程式编程。

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
