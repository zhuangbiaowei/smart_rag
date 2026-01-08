# JavaScript 开发指南

JavaScript 是一种动态编程语言，主要用于 Web 开发。它可以在浏览器端和服务器端（Node.js）运行。

## 基本语法

JavaScript 的语法与 C 系列语言相似：

```javascript
let name = "JavaScript";
const pi = 3.14159;
var oldWay = "legacy";

// 数组
const numbers = [1, 2, 3, 4, 5];

// 对象
const person = {
    name: "Alice",
    age: 30,
    greet: function() {
        return `Hello, ${this.name}!`;
    }
};
```

## 函数

JavaScript 支持多种函数定义方式：

```javascript
// 传统函数
function add(a, b) {
    return a + b;
}

// 箭头函数
const multiply = (a, b) => a * b;

// 箭头函数（多行）
const divide = (a, b) => {
    if (b === 0) {
        throw new Error("Cannot divide by zero");
    }
    return a / b;
};
```

## 异步编程

JavaScript 以异步编程闻名，主要使用 Promise 和 async/await：

```javascript
// Promise
fetch('/api/data')
    .then(response => response.json())
    .then(data => console.log(data))
    .catch(error => console.error(error));

// async/await
async function fetchData() {
    try {
        const response = await fetch('/api/data');
        const data = await response.json();
        return data;
    } catch (error) {
        console.error(error);
    }
}
```

## DOM 操作

JavaScript 可以动态修改网页内容：

```javascript
// 获取元素
const element = document.getElementById('myElement');

// 修改内容
element.textContent = 'New content';

// 添加事件监听
element.addEventListener('click', () => {
    alert('Clicked!');
});
```

## ES6+ 新特性

- **解构赋值**: `const {name, age} = person;`
- **模板字符串**: \`Hello, ${name}!\`
- **类语法**: `class MyClass { ... }`
- **模块化**: `import/export`

JavaScript 是现代 Web 开发的核心技术之一，配合 HTML 和 CSS 构建交互式的 Web 应用程序。

## English Summary

JavaScript powers web development in browsers and Node.js. This guide covers syntax, functions, async programming with Promise and async/await, and DOM manipulation.

## 日本語サマリー

JavaScript はブラウザと Node.js で動作する言語です。基本文法、関数、非同期処理（Promise、async/await）、DOM 操作を扱います。

## Résumé en français

JavaScript est un langage dynamique pour le web. Ce guide présente la syntaxe, les fonctions, l'asynchrone (Promise, async/await) et la manipulation du DOM.
