import 'package:flutter/material.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نظام إدارة المخزون',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const InventoryManagementScreen(),
    );
  }
}

class InventoryManagementScreen extends StatefulWidget {
  const InventoryManagementScreen({super.key});

  @override
  State<InventoryManagementScreen> createState() => _InventoryManagementScreenState();
}

class _InventoryManagementScreenState extends State<InventoryManagementScreen> {
  int _currentIndex = 0;
  late Database _database;
  List<Map<String, dynamic>> _inventoryItems = [];
  List<Map<String, dynamic>> _filteredItems = [];

  final TextEditingController _itemNameController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _purchasePriceController = TextEditingController();
  final TextEditingController _sellingPriceController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _warningController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  int _editIndex = -1;
  bool _isLoadingBarcode = false;

  double _totalSalePrice = 0.0;
  int _currentQuantity = 0;
  String? _currentBarcode;
  double _itemPrice = 0.0;

  @override
  void initState() {
    super.initState();
    _initDatabase();
    _searchController.addListener(_filterItems);
  }

  Future<void> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final dbPath = path.join(databasePath, 'inventory.db');

    _database = await openDatabase(
        dbPath,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
          CREATE TABLE inventory(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            itemName TEXT NOT NULL,
            barcode TEXT,
            purchasePrice REAL,
            sellingPrice REAL,
            quantity INTEGER,
            warningLevel INTEGER,
            date TEXT,
            createdAt TEXT
          )
        ''');
          await db.execute('''
          CREATE TABLE sales_history(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT,
            quantity INTEGER,
            totalPrice REAL,
            saleDate TEXT
          )
        ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('''
            CREATE TABLE sales_history(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              barcode TEXT,
              quantity INTEGER,
              totalPrice REAL,
              saleDate TEXT
            )
          ''');
          }
        }
    );

    await _loadInventory();
    setState(() => _isLoading = false);
  }

  Future<void> _loadInventory() async {
    final items = await _database.query('inventory');
    setState(() {
      _inventoryItems = items;
      _filteredItems = List.from(_inventoryItems);
    });
  }

  Future<void> _saveItem() async {
    if (_itemNameController.text.isEmpty) {
      _showMessage(context, 'يرجى إدخال اسم السلعة');
      return;
    }

    final itemData = {
      'itemName': _itemNameController.text,
      'barcode': _barcodeController.text,
      'purchasePrice': double.tryParse(_purchasePriceController.text) ?? 0.0,
      'sellingPrice': double.tryParse(_sellingPriceController.text) ?? 0.0,
      'quantity': int.tryParse(_quantityController.text) ?? 0,
      'warningLevel': int.tryParse(_warningController.text) ?? 0,
      'date': _dateController.text,
      'createdAt': DateTime.now().toIso8601String(),
    };

    try {
      if (_editIndex == -1) {
        await _database.insert('inventory', itemData);
        _showMessage(context, 'تمت إضافة الصنف بنجاح');
      } else {
        await _database.update(
          'inventory',
          itemData,
          where: 'id = ?',
          whereArgs: [_inventoryItems[_editIndex]['id']],
        );
        _showMessage(context, 'تم تحديث الصنف بنجاح');
        _editIndex = -1;
      }
      await _loadInventory();
      _clearForm();
    } catch (e) {
      _showMessage(context, 'حدث خطأ أثناء الحفظ: ${e.toString()}');
    }
  }

  Future<void> _deleteItem(int index) async {
    if (index < 0 || index >= _inventoryItems.length) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف هذا الصنف؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _database.delete(
          'inventory',
          where: 'id = ?',
          whereArgs: [_inventoryItems[index]['id']],
        );
        await _loadInventory();
        _showMessage(context, 'تم حذف الصنف بنجاح');
      } catch (e) {
        _showMessage(context, 'حدث خطأ أثناء الحذف: ${e.toString()}');
      }
    }
  }

  void _filterItems() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = _inventoryItems.where((item) {
        final nameMatch = item['itemName']?.toString().toLowerCase().contains(query) ?? false;
        final barcodeMatch = item['barcode']?.toString().toLowerCase().contains(query) ?? false;
        return nameMatch || barcodeMatch;
      }).toList();
    });
  }

  @override
  void dispose() {
    _database.close();
    _itemNameController.dispose();
    _barcodeController.dispose();
    _purchasePriceController.dispose();
    _sellingPriceController.dispose();
    _quantityController.dispose();
    _warningController.dispose();
    _dateController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('نظام إدارة المخزون'),
        centerTitle: true,
      ),
      body: _currentIndex == 0
          ? _buildAddItemForm()
          : _currentIndex == 1
          ? _buildInventoryTable()
          : _buildSaleInterface(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.add),
            label: 'إضافة صنف',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'عرض المخزون',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.point_of_sale),
            label: 'البيع',
          ),
        ],
      ),
    );
  }

  Widget _buildAddItemForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          _buildInputField(
            controller: _itemNameController,
            labelText: 'اسم السلعة',
            hintText: 'أدخل اسم السلعة',
            icon: Icons.shopping_bag,
          ),
          const SizedBox(height: 15),
          _buildBarcodeField(),
          const SizedBox(height: 15),
          _buildInputField(
            controller: _purchasePriceController,
            labelText: 'ثمن الشراء',
            hintText: 'أدخل سعر الشراء',
            icon: Icons.attach_money,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 15),
          _buildInputField(
            controller: _sellingPriceController,
            labelText: 'ثمن البيع',
            hintText: 'أدخل سعر البيع',
            icon: Icons.money_off_csred,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 15),
          _buildInputField(
            controller: _quantityController,
            labelText: 'الكمية المتاحة',
            hintText: 'أدخل الكمية',
            icon: Icons.inventory,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 15),
          _buildInputField(
            controller: _warningController,
            labelText: 'حد التحذير',
            hintText: 'أدخل الحد الأدنى للتحذير',
            icon: Icons.warning_amber,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 15),
          _buildInputField(
            controller: _dateController,
            labelText: 'تاريخ الإدخال',
            hintText: 'اختر تاريخ الإدخال',
            icon: Icons.calendar_today,
            isDate: true,
            onIconPressed: () => _selectDate(context),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _saveItem,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
            child: Text(
              _editIndex == -1 ? 'حفظ البيانات' : 'تحديث البيانات',
              style: const TextStyle(fontSize: 18),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBarcodeField() {
    return TextField(
      controller: _barcodeController,
      decoration: InputDecoration(
        labelText: 'كود الباركود',
        hintText: 'ادخل الكود أو اضغط أيقونة الكاميرا',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.qr_code),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_barcodeController.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _barcodeController.clear();
                  setState(() {});
                },
              ),
            IconButton(
              icon: const Icon(Icons.camera_alt),
              onPressed: _scanAndFillBarcode,
            ),
          ],
        ),
      ),
      keyboardType: TextInputType.number,
    );
  }

  Future<void> _scanAndFillBarcode() async {
    try {
      final result = await BarcodeScanner.scan();
      if (result.rawContent.isNotEmpty && mounted) {
        setState(() {
          _barcodeController.text = result.rawContent;
        });
      }
    } catch (e) {
      if (mounted) {
        _showMessage(context, 'خطأ في المسح: ${e.toString()}');
      }
    }
  }

  Widget _buildInventoryTable() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'ابحث باسم السلعة أو كود الباركود',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _filterItems();
                      },
                    ),
                  if (_barcodeController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _barcodeController.clear();
                        setState(() {});
                      },
                    ),
                ],
              ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => _filterItems(),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _filteredItems.isEmpty && _searchController.text.isNotEmpty
                  ? Center(
                child: Text(
                  "⚠️ العنصر غير موجود",
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 18,
                  ),
                ),
              )
                  : DataTable(
                columns: const [
                  DataColumn(label: Text('ID')),
                  DataColumn(label: Text('اسم السلعة')),
                  DataColumn(label: Text('كود الباركود')),
                  DataColumn(label: Text('الكمية')),
                  DataColumn(label: Text('حد التحذير')),
                  DataColumn(label: Text('سعر الشراء')),
                  DataColumn(label: Text('سعر البيع')),
                  DataColumn(label: Text('الإجراءات')),
                ],
                rows: List<DataRow>.generate(_filteredItems.length, (index) {
                  final item = _filteredItems[index];
                  final isLowStock = (item['quantity'] ?? 0) <= (item['warningLevel'] ?? 0);

                  return DataRow(
                    cells: [
                      DataCell(Text(item['id']?.toString() ?? '0')),
                      DataCell(Text(item['itemName']?.toString() ?? '')),
                      DataCell(Text(item['barcode']?.toString() ?? '-')),
                      DataCell(
                        Text(
                          item['quantity']?.toString() ?? '0',
                          style: TextStyle(
                            color: isLowStock ? Colors.red : Colors.black,
                            fontWeight: isLowStock ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      DataCell(Text(item['warningLevel']?.toString() ?? '0')),
                      DataCell(Text(item['purchasePrice']?.toString() ?? '0')),
                      DataCell(Text(item['sellingPrice']?.toString() ?? '0')),
                      DataCell(Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () {
                              final fullIndex = _inventoryItems.indexWhere(
                                      (i) => i['id'] == item['id']
                              );
                              if (fullIndex != -1) {
                                _editItem(fullIndex);
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              final fullIndex = _inventoryItems.indexWhere(
                                      (i) => i['id'] == item['id']
                              );
                              if (fullIndex != -1) {
                                _deleteItem(fullIndex);
                              }
                            },
                          ),
                        ],
                      )),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaleInterface() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: MediaQuery.of(context).size.height * 0.3,
            color: Colors.black,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'الوقت: ${DateFormat('HH:mm:ss').format(DateTime.now())}',
                      style: const TextStyle(
                        fontFamily: 'Digital7',
                        color: Colors.green,
                        fontSize: 20,
                      ),
                    ),
                    Text(
                      'السلع: ${_inventoryItems.length}',
                      style: const TextStyle(
                        fontFamily: 'Digital7',
                        color: Colors.green,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  '${_totalSalePrice.toStringAsFixed(2)} DZ',
                  style: TextStyle(
                    fontFamily: 'Digital7',
                    color: Colors.green,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.greenAccent.withOpacity(0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'الكمية: $_currentQuantity',
                  style: const TextStyle(
                    fontFamily: 'Digital7',
                    color: Colors.green,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _barcodeController,
              decoration: InputDecoration(
                labelText: 'كود الباركود',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.barcode_reader),
                  onPressed: _openBarcodeScanner,
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              FloatingActionButton(
                onPressed: () {
                  if (_barcodeController.text.isEmpty) {
                    _showMessage(context, 'يرجى إدخال كود الباركود');
                    return;
                  }

                  final product = _inventoryItems.firstWhere(
                        (item) => item['barcode'] == _barcodeController.text,
                    orElse: () => {},
                  );

                  if (product.isNotEmpty) {
                    setState(() {
                      _currentBarcode = _barcodeController.text;
                      _itemPrice = (product['sellingPrice'] ?? 0).toDouble();
                      _currentQuantity += 1;
                      _totalSalePrice += _itemPrice;
                      _barcodeController.clear();
                    });
                  } else {
                    _showMessage(context, 'المنتج غير موجود في المخزون');
                  }
                },
                backgroundColor: Colors.green,
                child: const Icon(Icons.check),
              ),
              FloatingActionButton(
                onPressed: () {
                  if (_currentBarcode == null) {
                    _showMessage(context, 'لم يتم تحديد أي منتج');
                    return;
                  }
                  setState(() {
                    _currentQuantity++;
                    _totalSalePrice += _itemPrice;
                  });
                },
                backgroundColor: Colors.blue,
                child: const Icon(Icons.add),
              ),
              FloatingActionButton(
                onPressed: () async {
                  if (_currentBarcode == null || _currentQuantity == 0) {
                    _showMessage(context, 'لم يتم تحديد أي منتج أو كمية');
                    return;
                  }

                  final productIndex = _inventoryItems.indexWhere(
                          (item) => item['barcode'] == _currentBarcode
                  );

                  if (productIndex == -1) {
                    _showMessage(context, 'المنتج غير موجود في المخزون');
                    return;
                  }

                  final availableQty = _inventoryItems[productIndex]['quantity'] ?? 0;
                  if (availableQty < _currentQuantity) {
                    _showMessage(context, 'الكمية غير كافية. المتاح: $availableQty');
                    return;
                  }

                  try {
                    await _database.update(
                      'inventory',
                      {'quantity': availableQty - _currentQuantity},
                      where: 'id = ?',
                      whereArgs: [_inventoryItems[productIndex]['id']],
                    );

                    await _addSaleToHistory();

                    setState(() {
                      _barcodeController.clear();
                      _totalSalePrice = 0.0;
                      _currentQuantity = 0;
                      _currentBarcode = null;
                    });

                    await _loadInventory();
                    _showMessage(context, 'تم تأكيد عملية البيع بنجاح');
                  } catch (e) {
                    _showMessage(context, 'حدث خطأ أثناء عملية البيع: ${e.toString()}');
                  }
                },
                backgroundColor: Colors.orange,
                child: const Icon(Icons.done_all),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addSaleToHistory() async {
    if (_currentBarcode == null || _currentQuantity <= 0) return;

    try {
      await _database.insert('sales_history', {
        'barcode': _currentBarcode,
        'quantity': _currentQuantity,
        'totalPrice': _totalSalePrice,
        'saleDate': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error saving sale history: $e');
    }
  }

  Future<void> _openBarcodeScanner() async {
    setState(() => _isLoadingBarcode = true);
    try {
      final result = await BarcodeScanner.scan();
      if (result.rawContent.isNotEmpty && mounted) {
        setState(() {
          _barcodeController.text = result.rawContent;
        });
      }
    } catch (e) {
      if (mounted) {
        _showMessage(context, 'حدث خطأ: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingBarcode = false);
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  void _editItem(int index) {
    if (index < 0 || index >= _inventoryItems.length) return;

    final item = _inventoryItems[index];
    if (item.isEmpty) return;

    setState(() {
      _editIndex = index;
      _itemNameController.text = item['itemName'] ?? '';
      _barcodeController.text = item['barcode'] ?? '';
      _purchasePriceController.text = item['purchasePrice']?.toString() ?? '0';
      _sellingPriceController.text = item['sellingPrice']?.toString() ?? '0';
      _quantityController.text = item['quantity']?.toString() ?? '0';
      _warningController.text = item['warningLevel']?.toString() ?? '0';
      _dateController.text = item['date'] ?? '';
      _currentIndex = 0;
    });
  }

  void _clearForm() {
    _itemNameController.clear();
    _barcodeController.clear();
    _purchasePriceController.clear();
    _sellingPriceController.clear();
    _quantityController.clear();
    _warningController.clear();
    _dateController.clear();
  }

  void _showMessage(BuildContext context, String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData icon,
    bool isBarcode = false,
    bool isDate = false,
    bool isLoading = false,
    TextInputType keyboardType = TextInputType.text,
    VoidCallback? onIconPressed,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon, color: Colors.blue),
        suffixIcon: isBarcode || isDate
            ? isLoading
            ? const Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        )
            : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isBarcode && controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear, size: 20),
                onPressed: () {
                  controller.clear();
                  if (onIconPressed != null) onIconPressed();
                },
              ),
            IconButton(
              icon: Icon(
                isBarcode ? Icons.camera_alt : Icons.calendar_month,
                color: Colors.blue,
              ),
              onPressed: onIconPressed,
            ),
          ],
        )
            : null,
      ),
      keyboardType: isBarcode ? TextInputType.number : keyboardType,
      readOnly: isDate,
      onTap: isDate ? onIconPressed : null,
    );
  }
}
