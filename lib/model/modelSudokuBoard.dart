import 'package:flutter/material.dart';
import 'package:fsudoku/model/modelSudokuCell.dart';
import 'package:fsudoku/model/modelSudokuMethod.dart';
import 'package:fsudoku/widget/widgetKeypad.dart';
import 'package:preferences/preferences.dart';

enum SudokuKeypadMode {
  /* 草稿模式 */ Draft,
  /* 直接填写一个数字 */ Fill,
}

// 难度级别，这里只是代表题目出来后，有多少个数字
const Difficult_Easy = 32;
const Difficult_Hard = 25;
const Difficult_VeryHard = 21;
const Difficult_VeryVeryHard = 16;
const Difficult_Default = Difficult_Hard;

// 所有数据都在这里啦
class SudokuBoardViewModel {
  List<SudokuCellViewModel> cells;
  // 据了解，dart里一切皆对象，（可以理解为指针？）
  // 原始数据
  List<int> raw;
  List<int> rawWithAnswer;
  // 用于存档功能
  List<Cell> cellsBakup;
  // 用于记录操作
  List<List<Cell>> redos;
  // 所有行、列、九宫格，便于引用与检查
  List<List<SudokuCellViewModel>> rows;
  List<List<SudokuCellViewModel>> cols;
  List<List<SudokuCellViewModel>> blocks;
  // 当前处于激活状态的cell
  SudokuCellViewModel focusedCell;
  // SudokuCellViewModel hoveredCell;
  // 当前需要显示激活状态的cell们
  Set<SudokuCellViewModel> focusedCells = Set();
  // 含有相同数字的cell们
  Set<SudokuCellViewModel> sameNumberCells = Set();
  int curNumber = Number_Invalid;
  // 当前需要显示为鼠标移过状态的cell们
  Set<SudokuCellViewModel> hoveredCells = Set();
  // 当前显示为警告的cell们，之所以不用error是因为字母不对齐
  // Set<SudokuCellViewModel> warningCells = Set();
  // bool hasErrors = false;

  // 键盘的把柄，让你重画就重画
  GlobalKey<SudokuKeypadState> keypadKey;
  // 键盘的输入模式，感觉放这不是个好主意
  SudokuKeypadMode keypadMode = SudokuKeypadMode.Draft;

  // TODO:寻找更好的实现方式
  GlobalKey<ScaffoldState> scaffoldKey;

  // 构造函数
  SudokuBoardViewModel() {
    cells = List<SudokuCellViewModel>.generate(
        81, (_) => SudokuCellViewModel(this),
        growable: false);

    // 方便UI处理
    rows = List(9);
    cols = List(9);
    blocks = List(9);
    for (int i = 0; i < 9; i++) {
      rows[i] = List(9);
      cols[i] = List(9);
      blocks[i] = List(9);
      for (int j = 0; j < 9; j++) {
        rows[i][j] = cells[i * 9 + j];
        rows[i][j].rowInBoard = i;
        cols[i][j] = cells[j * 9 + i];
        cols[i][j].colInBoard = i;
        blocks[i][j] =
            cells[(i ~/ 3) * 27 + (j ~/ 3) * 9 + (i % 3) * 3 + j % 3];
        blocks[i][j].blockInBoard = i;
      }
    }

    // 生成数独的线程
    // TODO:后台生成一定数量的数独题目，比如最多10个，下一个题目可以随时读取

    // FOR TEST ONLY
    // cells.forEach((element) {
    //   element.addCandidateNumber(Random().nextInt(9) + 1);
    // element.addCandidateNumber(Random().nextInt(9) + 1);
    // element.isFixed = Random().nextBool();
    //   element.isFixed = false;
    // });

    // FOR TEST ONLY
    // 随机生成10个数字，测试自动填充的功能
    // int n = 10;
    // raw = List.generate(81, (index) => Number_Invalid, growable: false);
    // while (n > 0) {
    //   int x = Random().nextInt(81);
    //   int v = Random().nextInt(9) + 1;
    //   raw[x] = v;
    //   cells[x].filledNumber = v;
    //   cells[x].isFixed = true;
    //   n--;
    // }

    // FOR TEST ONLY
    // fromString(
    //     '048503070060004100100090025700150302006007500802400006470080001009700040080302950');

    newModel(Difficult_Default);
  }

  // 依次生成数独题目的字符串，0表示
  @override
  String toString() {
    StringBuffer sb = StringBuffer();
    for (int i = 0; i < 81; i++) {
      sb.write(raw[i]);
    }
    return sb.toString();
  }

  // 生成比较好看的形式，includeAnswer:是否包含答案？
  String toStringEx(bool includeAnswer) {
    StringBuffer sb = StringBuffer();
    sb.writeln('-------------------');
    for (int i = 0; i < 9; i++) {
      sb.write('|');
      for (int j = 0; j < 9; j++) {
        // 当格子上的数字是固定的，输出
        // 如果需要输出自己填写的数字，得判断一下是否唯一，然后输出
        // 否则输出0
        if (includeAnswer) {
          sb.write(rawWithAnswer[i * 9 + j]);
        } else {
          sb.write(raw[i * 9 + j]);
        }
        sb.write('|');
      }
      sb.writeln();
    }
    sb.writeln('-------------------');
    return sb.toString();
  }

  // 深拷贝列表内容，因为如果改变了cells的指向的话，rows、cols、blocks这仨会出问题的
  void copyCells(List<SudokuCellViewModel> src, List<SudokuCellViewModel> dst) {
    for (int i = 0; i < 81; i++) {
      dst[i].isFixed = src[i].isFixed;
      dst[i].rowInBoard = src[i].rowInBoard;
      dst[i].colInBoard = src[i].colInBoard;
      dst[i].blockInBoard = src[i].blockInBoard;
      // ?
      dst[i].candidateNumbers = src[i].candidateNumbers;
    }
  }

  // 假定是标准形式，一溜的字符串，长度为81
  // true转换成功，false转换失败
  bool fromString(String str) {
    if (str.length != 81) return false;

    List<int> newCells = List(81);
    for (int i = 0; i < 81; i++) {
      try {
        newCells[i] = int.tryParse(str[i]);
      } catch (e) {
        return false;
      }
    }
    clearCells();
    for (int i = 0; i < 81; i++) {
      cells[i].filledNumber = newCells[i];
      cells[i].isFixed = (newCells[i] != 0);
    }
    raw = newCells;
    return true;
  }

  // 生成一个新题的接口，level代表有多少个已知数
  void newModel(int level) {
    List<List<int>> field = List.generate(
        9, (index) => List.generate(9, (index) => 0, growable: false),
        growable: false);
    List<List<bool>> rows =
        List.generate(9, (index) => List.generate(9, (index) => false));
    List<List<bool>> cols =
        List.generate(9, (index) => List.generate(9, (index) => false));
    List<List<bool>> blocks =
        List.generate(9, (index) => List.generate(9, (index) => false));

    while (!lasVegas(field, rows, cols, blocks, 11)) {
      clearFRCB(field, rows, cols, blocks);
    }

    digSudoku(field, rows, cols, blocks, level);

    for (int i = 0; i < 9; i++) {
      for (int j = 0; j < 9; j++) {
        int v = field[i][j];
        cells[i * 9 + j].isWrong = false;
        cells[i * 9 + j].isFixed = (v != Number_Invalid);
        cells[i * 9 + j].filledNumber = v;
      }
    }

    if (PrefService.getBool('sudoku_autofill')) _calAllCandidateNumber();
  }

  // 求同一行、一列、一九宫格的单元格的集合
  Set<SudokuCellViewModel> _calSameRowColBlockCells(SudokuCellViewModel cell) {
    Set<SudokuCellViewModel> ret = Set();
    ret.addAll(rows[cell.rowInBoard]);
    ret.addAll(cols[cell.colInBoard]);
    ret.addAll(blocks[cell.blockInBoard]);
    return ret;
  }

  // 求含有同一数字的集合
  Set<SudokuCellViewModel> _calSameNumberCells(SudokuCellViewModel cell) {
    Set<SudokuCellViewModel> ret = Set();
    if (cell.filledNumber != Number_Invalid)
      cells.forEach((element) {
        if (element.filledNumber != Number_Invalid) {
          if (element.filledNumber == cell.filledNumber) {
            ret.add(element);
          }
        } else {
          if (element.listCandidateNumbers().contains(cell.filledNumber)) {
            ret.add(element);
          }
        }
      });
    return ret;
  }

  void _refreshAllCell() {
    cells.forEach((element) {
      element.notifyRefresh();
    });
  }

  // 处理单元格按下事件
  // 已知原来有的，求出和新的有关的，求交集，交集不用变，原有的-交集=需要告诉它们恢复原样
  // 新来的-交集=需要通知它们作出改变
  // 画个伟恩图就好，感觉是不是想多了我
  void handleCellTap(SudokuCellViewModel cell) {
    // Set<SudokuCellViewModel> oldCells = focusedCells;
    // Set<SudokuCellViewModel> newCells1 = _calSameRowColBlockCells(cell);
    // Set<SudokuCellViewModel> newCells2 = _calSameNumberCells(cell);
    // focusedCells = newCells1;
    // sameNumberCells = newCells2;

    focusedCell = cell;
    focusedCells = _calSameRowColBlockCells(cell);
    sameNumberCells = _calSameNumberCells(cell);
    curNumber = cell.filledNumber;

    _refreshAllCell();

    // tmp3.forEach((element) {
    //   element.notifyRefresh();
    // });

    keypadKey?.currentState?.setFocusedCell(cell);
  }

  // 同上，对鼠标移过的也算一算
  void handleCellHover(SudokuCellViewModel cell) {
    Set<SudokuCellViewModel> oldCells = hoveredCells;
    Set<SudokuCellViewModel> newCells = _calSameRowColBlockCells(cell);

    hoveredCells = newCells;

    newCells.union(oldCells).forEach((element) {
      element.notifyRefresh();
    });
  }

  // 处理按下键盘时的事件
  // 首先判断是否可以接受输入，
  // 然后判断当前的输入模式，
  // 如果是直接输入模式，设定数字值，检查当前影响的格子的行列宫中，是否存在可消除的候选数字
  // 如果是草稿输入模式，设定/移除候选数字，移除候选数字时，如果候选数字唯一，根据设置使候选数字上屏
  // 检查是否有错误数字，如果已经填满，检查是否正确，正确时弹窗处理
  void handleKeypadTap(SudokuCellViewModel cell, int number) {
    if (cell.isFixed) return;

    // TODO: 记录

    Set<SudokuCellViewModel> affect = Set();
    Set<SudokuCellViewModel> oldErrors = _calErrorCells(cell);
    if (keypadMode == SudokuKeypadMode.Fill) {
      // Fill Mode
      affect.addAll(setNumber(cell, number));
    } else {
      // Draft Mode
      affect.addAll(toggleCandidateNumber(cell, number));
    }
    // 修改完以后，找到相关的错误
    oldErrors.forEach((element) {
      // if (element == cell) return;
      Set<SudokuCellViewModel> tmp = _calErrorCells(element);
      if (tmp.isEmpty) {
        // 这就属于改正好的结果
        element.isWrong = false;
        affect.add(element);
      } // 这些格子还有错误的其他情况，这里不管
    });
    Set<SudokuCellViewModel> newErrors = _calErrorCells(cell);
    newErrors.forEach((element) {
      element.isWrong = true;
      affect.add(element);
    });
    affect.add(cell);

    affect.forEach((element) {
      element.notifyRefresh();
    });
    keypadKey.currentState.refresh();

    handleCellTap(cell);

    // 检查是否符合要求
    // 最后一次填写没有错误，且所有格子均已填写完毕，那么肯定是正确的
    if (newErrors.isEmpty &&
        (!cells.any((element) => element.filledNumber == Number_Invalid))) {
      scaffoldKey.currentState.showSnackBar(SnackBar(
        content: Text('Win!'),
      ));
    }
  }

  Set<SudokuCellViewModel> toggleCandidateNumber(
      SudokuCellViewModel cell, int number) {
    Set<SudokuCellViewModel> ret = Set();
    bool old = cell.candidateNumbers[number - 1];

    ret.addAll(old
        ? removeCandidateNumber(cell, number)
        : addCandidateNumber(cell, number));

    return ret;
  }

  Set<SudokuCellViewModel> addCandidateNumber(
      SudokuCellViewModel cell, int number) {
    cell.candidateNumbers[number - 1] = true;
    cell.filledNumber = Number_Invalid;
    return Set()..add(cell);
  }

  Set<SudokuCellViewModel> removeCandidateNumber(
      SudokuCellViewModel cell, int number) {
    Set<SudokuCellViewModel> ret = Set();
    if (cell.candidateNumbers[number - 1]) {
      cell.candidateNumbers[number - 1] = false;
      ret.add(cell);
      if (cell.filledNumber == number) {
        cell.filledNumber = Number_Invalid;
      } else {
        List<int> tmp = cell.listCandidateNumbers();
        if (PrefService.getBool('sudoku_autonumber') && tmp.length == 1) {
          ret.addAll(setNumber(cell, tmp[0]));
        } else {
          cell.filledNumber = Number_Invalid;
        }
      }
    }
    return ret;
  }

  Set<SudokuCellViewModel> setNumber(SudokuCellViewModel cell, int number) {
    Set<SudokuCellViewModel> ret = Set();
    for (int i = 0; i < 9; i++) {
      cell.candidateNumbers[i] = (i == (number - 1));
    }
    cell.filledNumber = number;

    // 设定数字之后，需要清除同行同列同宫中的候选数字
    Set<SudokuCellViewModel> tmp = _calSameRowColBlockCells(cell);
    tmp.forEach((element) {
      if ((!element.isFixed) && element.filledNumber == Number_Invalid) {
        ret.addAll(removeCandidateNumber(element, number));
      }
    });
    return ret;
  }

  // 清空内容
  void clearCells() {
    cells.forEach((element) {
      element.candidateNumbers.forEach((element1) {
        element1 = false;
      });
      element.isFixed = false;
      element.filledNumber = Number_Invalid;
    });
  }

  // 计算候选数字，有且仅有在数独开始时使用
  // 直接操作内部数组
  // 这个时候number肯定只有固定的数字
  void _calAllCandidateNumber() {
    List<List<bool>> r = List.generate(
        9,
        (i) => List.generate(
            9,
            (j) => rows[i].any((element) =>
                (element.filledNumber != Number_Invalid &&
                    element.filledNumber == j + 1))));
    List<List<bool>> c = List.generate(
        9,
        (i) => List.generate(
            9,
            (j) => cols[i].any((element) =>
                (element.filledNumber != Number_Invalid &&
                    element.filledNumber == j + 1))));
    List<List<bool>> b = List.generate(
        9,
        (i) => List.generate(
            9,
            (j) => blocks[i].any((element) =>
                (element.filledNumber != Number_Invalid &&
                    element.filledNumber == j + 1))));
    cells.forEach((element) {
      if (!element.isFixed) {
        // 依次判断这个格子是否能填1-9
        for (int i = 0; i < 9; i++)
          if (!r[element.rowInBoard][i] &&
              !c[element.colInBoard][i] &&
              !b[element.blockInBoard][i]) {
            element.candidateNumbers[i] = true;
          }
      }
    });
  }

  // 找到与cell冲突的格子
  Set<SudokuCellViewModel> _calErrorCells(SudokuCellViewModel cell) {
    Set<SudokuCellViewModel> tmp = _calSameRowColBlockCells(cell);
    Set<SudokuCellViewModel> ret = Set();
    if (cell.filledNumber != Number_Invalid) {
      tmp.forEach((element) {
        if (element == cell) return;
        if (element.filledNumber != Number_Invalid) {
          if (element.filledNumber == cell.filledNumber) {
            ret.add(element);
          }
        } else {
          if (element.listCandidateNumbers().contains(cell.filledNumber)) {
            ret.add(element);
          }
        }
      });
    } else {
      tmp.forEach((element) {
        if (element == cell) return;
        if (element.filledNumber != Number_Invalid) {
          if (cell.listCandidateNumbers().contains(element.filledNumber))
            ret.add(element);
        }
      });
    }
    if (ret.isNotEmpty) ret.add(cell);
    return ret;
  }
}
