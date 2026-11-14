import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GurukrupaApp());
}

class GurukrupaApp extends StatelessWidget {
  const GurukrupaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gurukrupa Quotation Maker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B1E24)),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF8B1E24),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ==================== MODELS ====================

class LineItem {
  String name;
  double quantity;
  double rate;

  LineItem({required this.name, required this.quantity, required this.rate});

  double get amount => quantity * rate;

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'rate': rate,
      };

  factory LineItem.fromJson(Map<String, dynamic> json) => LineItem(
        name: json['name'] ?? '',
        quantity: (json['quantity'] ?? 0).toDouble(),
        rate: (json['rate'] ?? 0).toDouble(),
      );
}

class QuotationDoc {
  int? id;
  String docType; // QUOTATION or INVOICE
  int docNumber;
  String date;
  String clientName;
  String clientAddress;
  String eventTitle;
  double taxPercent;
  double advancePaid;
  String notes;
  List<LineItem> items;

  QuotationDoc({
    this.id,
    required this.docType,
    required this.docNumber,
    required this.date,
    required this.clientName,
    required this.clientAddress,
    required this.eventTitle,
    this.taxPercent = 0.0,
    this.advancePaid = 0.0,
    this.notes = '',
    required this.items,
  });

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.amount);
  double get taxAmount => subtotal * (taxPercent / 100);
  double get total => subtotal + taxAmount;
  double get balanceDue => total - advancePaid;

  Map<String, dynamic> toMap() => {
        'id': id,
        'docType': docType,
        'docNumber': docNumber,
        'date': date,
        'clientName': clientName,
        'clientAddress': clientAddress,
        'eventTitle': eventTitle,
        'taxPercent': taxPercent,
        'advancePaid': advancePaid,
        'notes': notes,
        'itemsJson': jsonEncode(items.map((e) => e.toJson()).toList()),
      };

  factory QuotationDoc.fromMap(Map<String, dynamic> map) {
    final List<dynamic> decoded = jsonDecode(map['itemsJson'] ?? '[]');
    return QuotationDoc(
      id: map['id'],
      docType: map['docType'] ?? 'QUOTATION',
      docNumber: map['docNumber'] ?? 1,
      date: map['date'] ?? '',
      clientName: map['clientName'] ?? '',
      clientAddress: map['clientAddress'] ?? '',
      eventTitle: map['eventTitle'] ?? '',
      taxPercent: (map['taxPercent'] ?? 0).toDouble(),
      advancePaid: (map['advancePaid'] ?? 0).toDouble(),
      notes: map['notes'] ?? '',
      items: decoded.map((e) => LineItem.fromJson(e)).toList(),
    );
  }
}

class BusinessProfile {
  String firmName;
  String tagline;
  String proprietor;
  String phone;
  String city;
  String pan;
  String bankName;
  String accountHolder;
  String accountNumber;
  String ifsc;
  String branch;

  BusinessProfile({
    this.firmName = 'GURUKRUPA MANDAP & DECORATORS',
    this.tagline = 'YOUR AUSPICIOUS EVENT, OUR ARRANGEMENT...',
    this.proprietor = 'PRAKASH RATHOD',
    this.phone = '7972210277',
    this.city = 'CHHATRAPATI SAMBHAJINAGAR.',
    this.pan = 'CILPR2903N',
    this.bankName = 'AXIS BANK',
    this.accountHolder = 'PRAKASH VANSINGH RATHOD',
    this.accountNumber = '922010015774835',
    this.ifsc = 'UTIB0001731',
    this.branch = 'GARKHEDA 431005',
  });

  static Future<BusinessProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    return BusinessProfile(
      firmName: prefs.getString('firmName') ?? 'GURUKRUPA MANDAP & DECORATORS',
      tagline: prefs.getString('tagline') ?? 'YOUR AUSPICIOUS EVENT, OUR ARRANGEMENT...',
      proprietor: prefs.getString('proprietor') ?? 'PRAKASH RATHOD',
      phone: prefs.getString('phone') ?? '7972210277',
      city: prefs.getString('city') ?? 'CHHATRAPATI SAMBHAJINAGAR.',
      pan: prefs.getString('pan') ?? 'CILPR2903N',
      bankName: prefs.getString('bankName') ?? 'AXIS BANK',
      accountHolder: prefs.getString('accountHolder') ?? 'PRAKASH VANSINGH RATHOD',
      accountNumber: prefs.getString('accountNumber') ?? '922010015774835',
      ifsc: prefs.getString('ifsc') ?? 'UTIB0001731',
      branch: prefs.getString('branch') ?? 'GARKHEDA 431005',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('firmName', firmName);
    await prefs.setString('tagline', tagline);
    await prefs.setString('proprietor', proprietor);
    await prefs.setString('phone', phone);
    await prefs.setString('city', city);
    await prefs.setString('pan', pan);
    await prefs.setString('bankName', bankName);
    await prefs.setString('accountHolder', accountHolder);
    await prefs.setString('accountNumber', accountNumber);
    await prefs.setString('ifsc', ifsc);
    await prefs.setString('branch', branch);
  }
}

// ==================== DATABASE HELPER (INTERNAL STORAGE CRUD) ====================

class DBHelper {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'gurukrupa_quotations.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE quotations(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            docType TEXT,
            docNumber INTEGER,
            date TEXT,
            clientName TEXT,
            clientAddress TEXT,
            eventTitle TEXT,
            taxPercent REAL,
            advancePaid REAL,
            notes TEXT,
            itemsJson TEXT
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<int> insert(QuotationDoc doc) async {
    final db = await database;
    return await db.insert('quotations', doc.toMap());
  }

  static Future<int> update(QuotationDoc doc) async {
    final db = await database;
    return await db.update(
      'quotations',
      doc.toMap(),
      where: 'id = ?',
      whereArgs: [doc.id],
    );
  }

  static Future<int> delete(int id) async {
    final db = await database;
    return await db.delete('quotations', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<QuotationDoc>> getAll() async {
    final db = await database;
    final maps = await db.query('quotations', orderBy: 'id DESC');
    return maps.map((m) => QuotationDoc.fromMap(m)).toList();
  }

  static Future<int> getNextDocNumber() async {
    final db = await database;
    final res = await db.rawQuery('SELECT MAX(docNumber) as maxNum FROM quotations');
    final maxNum = res.first['maxNum'] as int?;
    return (maxNum ?? 45) + 1;
  }
}

// ==================== PDF GENERATOR ====================

class PdfService {
  static final _currency = NumberFormat('#,##0.00', 'en_IN');

  static Future<void> generateAndShare(QuotationDoc doc, BusinessProfile profile) async {
    final pdf = pw.Document();
    final fontRegular = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    final primaryDark = PdfColor.fromHex('#2C2C2C');
    final accentRed = PdfColor.fromHex('#8B1E24');
    final lightBg = PdfColor.fromHex('#F4F4F4');
    final borderGrey = PdfColor.fromHex('#CCCCCC');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
        build: (context) => [
          // Header Banner
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      profile.firmName,
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: accentRed),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      profile.tagline,
                      style: pw.TextStyle(fontSize: 8.5, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(profile.proprietor, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text('${profile.firmName} (${profile.phone})', style: const pw.TextStyle(fontSize: 9.5)),
                    pw.Text(profile.city, style: const pw.TextStyle(fontSize: 9.5)),
                  ],
                ),
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      doc.docType.toUpperCase(),
                      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: primaryDark),
                    ),
                    pw.Text('# ${doc.docNumber}', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    pw.SizedBox(height: 10),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: pw.BoxDecoration(color: lightBg, borderRadius: pw.BorderRadius.circular(4)),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('Date: ${doc.date}', style: const pw.TextStyle(fontSize: 9.5)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Balance Due: ₹${_currency.format(doc.balanceDue)}',
                            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Divider(color: borderGrey),
          pw.SizedBox(height: 8),

          // Bill To
          pw.Text('Bill To:', style: pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(doc.clientName, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          if (doc.clientAddress.isNotEmpty)
            pw.Text(doc.clientAddress, style: const pw.TextStyle(fontSize: 9.5)),
          if (doc.eventTitle.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text('(${doc.eventTitle})', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
            ),
          pw.SizedBox(height: 14),

          // Items Table
          pw.TableHelper.fromTextArray(
            headers: ['Item', 'Quantity', 'Rate', 'Amount'],
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
            headerDecoration: pw.BoxDecoration(color: primaryDark),
            cellStyle: const pw.TextStyle(fontSize: 9.5),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(1.8),
              3: const pw.FlexColumnWidth(2),
            },
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            oddRowDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#FAFAFA')),
            data: doc.items.map((item) {
              final qtyStr = item.quantity % 1 == 0 ? item.quantity.toInt().toString() : item.quantity.toString();
              return [
                item.name,
                qtyStr,
                '₹${_currency.format(item.rate)}',
                '₹${_currency.format(item.amount)}',
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 16),

          // Totals & Signature
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(profile.firmName, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 28),
                  pw.Container(width: 120, height: 1, color: PdfColors.grey600),
                  pw.SizedBox(height: 3),
                  pw.Text('Proprietor', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              pw.Container(
                width: 210,
                child: pw.Column(
                  children: [
                    _summaryRow('Subtotal:', '₹${_currency.format(doc.subtotal)}'),
                    _summaryRow('Tax (${doc.taxPercent.toStringAsFixed(0)}%):', '₹${_currency.format(doc.taxAmount)}'),
                    if (doc.advancePaid > 0)
                      _summaryRow('Advance Paid:', '- ₹${_currency.format(doc.advancePaid)}'),
                    pw.Divider(color: primaryDark),
                    _summaryRow('Total:', '₹${_currency.format(doc.total)}', isBold: true),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Divider(color: borderGrey),
          pw.SizedBox(height: 6),

          // Notes & Bank Details
          if (doc.notes.isNotEmpty) ...[
            pw.Text('Notes:', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
            pw.Text(doc.notes, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 10),
          ],
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: lightBg,
              borderRadius: pw.BorderRadius.circular(4),
              border: pw.Border.all(color: borderGrey),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('BANK DETAILS:', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: accentRed)),
                pw.SizedBox(height: 3),
                pw.Text('PAN NUMBER: ${profile.pan}', style: const pw.TextStyle(fontSize: 8.8)),
                pw.Text('BANK NAME: ${profile.bankName}', style: const pw.TextStyle(fontSize: 8.8)),
                pw.Text('ACCOUNT HOLDER: ${profile.accountHolder}', style: const pw.TextStyle(fontSize: 8.8)),
                pw.Text('ACCOUNT NUMBER: ${profile.accountNumber}', style: const pw.TextStyle(fontSize: 8.8)),
                pw.Text('IFSC: ${profile.ifsc}  |  BRANCH: ${profile.branch}', style: const pw.TextStyle(fontSize: 8.8)),
              ],
            ),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final safeClient = doc.clientName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${doc.docType}_${doc.docNumber}_$safeClient.pdf',
    );
  }

  static pw.Widget _summaryRow(String label, String value, {bool isBold = false}) {
    final style = pw.TextStyle(
      fontSize: isBold ? 11 : 9.5,
      fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(label, style: style), pw.Text(value, style: style)],
      ),
    );
  }
}

// ==================== HOME SCREEN (LIST + SEARCH + CRUD) ====================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<QuotationDoc> _allDocs = [];
  List<QuotationDoc> _filteredDocs = [];
  final _searchController = TextEditingController();
  final _currency = NumberFormat('#,##0.00', 'en_IN');
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final docs = await DBHelper.getAll();
    setState(() {
      _allDocs = docs;
      _filter(_searchController.text);
      _loading = false;
    });
  }

  void _filter(String query) {
    if (query.trim().isEmpty) {
      _filteredDocs = List.from(_allDocs);
    } else {
      final q = query.toLowerCase();
      _filteredDocs = _allDocs.where((d) {
        return d.clientName.toLowerCase().contains(q) ||
            d.eventTitle.toLowerCase().contains(q) ||
            d.docNumber.toString().contains(q);
      }).toList();
    }
  }

  Future<void> _deleteDoc(QuotationDoc doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Confirmation'),
        content: Text('Delete ${doc.docType} #${doc.docNumber} (${doc.clientName})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true && doc.id != null) {
      await DBHelper.delete(doc.id!);
      _loadData();
    }
  }

  Future<void> _duplicateDoc(QuotationDoc doc) async {
    final nextNum = await DBHelper.getNextDocNumber();
    final copy = QuotationDoc(
      docType: doc.docType,
      docNumber: nextNum,
      date: DateFormat('MMM dd, yyyy').format(DateTime.now()),
      clientName: doc.clientName,
      clientAddress: doc.clientAddress,
      eventTitle: doc.eventTitle,
      taxPercent: doc.taxPercent,
      advancePaid: 0,
      notes: doc.notes,
      items: doc.items.map((i) => LineItem(name: i.name, quantity: i.quantity, rate: i.rate)).toList(),
    );
    await DBHelper.insert(copy);
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied as #${copy.docNumber}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gurukrupa Quotations', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Business & Bank Settings',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _filter(val)),
              decoration: InputDecoration(
                hintText: 'Search client, event, or # number...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _filter(''));
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredDocs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.description_outlined, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text('No Quotations Yet', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                            const SizedBox(height: 4),
                            const Text('Tap "+ New" below to create your first quote'),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 80),
                        itemCount: _filteredDocs.length,
                        itemBuilder: (context, index) {
                          final doc = _filteredDocs[index];
                          final isInvoice = doc.docType == 'INVOICE';
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isInvoice ? Colors.green.shade100 : Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${doc.docType} #${doc.docNumber}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: isInvoice ? Colors.green.shade900 : Colors.orange.shade900,
                                          ),
                                        ),
                                      ),
                                      Text(doc.date, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(doc.clientName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  if (doc.eventTitle.isNotEmpty)
                                    Text(doc.eventTitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                  const Divider(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Total: ₹${_currency.format(doc.total)}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                          if (doc.advancePaid > 0)
                                            Text('Due: ₹${_currency.format(doc.balanceDue)}',
                                                style: const TextStyle(color: Colors.red, fontSize: 12)),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.picture_as_pdf, color: Color(0xFF8B1E24)),
                                            tooltip: 'Share PDF',
                                            onPressed: () async {
                                              final profile = await BusinessProfile.load();
                                              await PdfService.generateAndShare(doc, profile);
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit, color: Colors.blue),
                                            tooltip: 'Edit',
                                            onPressed: () async {
                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(builder: (_) => FormScreen(existingDoc: doc)),
                                              );
                                              _loadData();
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.copy, color: Colors.teal),
                                            tooltip: 'Duplicate',
                                            onPressed: () => _duplicateDoc(doc),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                                            tooltip: 'Delete',
                                            onPressed: () => _deleteDoc(doc),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF8B1E24),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Quote'),
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const FormScreen()));
          _loadData();
        },
      ),
    );
  }
}

// ==================== CREATE / EDIT FORM SCREEN ====================

class FormScreen extends StatefulWidget {
  final QuotationDoc? existingDoc;
  const FormScreen({super.key, this.existingDoc});

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  final _formKey = GlobalKey<FormState>();
  String _docType = 'QUOTATION';
  final _docNumCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _clientNameCtrl = TextEditingController();
  final _clientAddrCtrl = TextEditingController();
  final _eventTitleCtrl = TextEditingController();
  final _taxCtrl = TextEditingController(text: '0');
  final _advanceCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();
  List<LineItem> _items = [];
  final _currency = NumberFormat('#,##0.00', 'en_IN');

  @override
  void initState() {
    super.initState();
    if (widget.existingDoc != null) {
      final d = widget.existingDoc!;
      _docType = d.docType;
      _docNumCtrl.text = d.docNumber.toString();
      _dateCtrl.text = d.date;
      _clientNameCtrl.text = d.clientName;
      _clientAddrCtrl.text = d.clientAddress;
      _eventTitleCtrl.text = d.eventTitle;
      _taxCtrl.text = d.taxPercent.toString();
      _advanceCtrl.text = d.advancePaid.toString();
      _notesCtrl.text = d.notes;
      _items = d.items.map((e) => LineItem(name: e.name, quantity: e.quantity, rate: e.rate)).toList();
    } else {
      _dateCtrl.text = DateFormat('MMM dd, yyyy').format(DateTime.now());
      _initNextNumber();
      _items.add(LineItem(name: 'Stage 16x20 ft', quantity: 1, rate: 5000));
    }
  }

  Future<void> _initNextNumber() async {
    final next = await DBHelper.getNextDocNumber();
    if (mounted) setState(() => _docNumCtrl.text = next.toString());
  }

  double get _subtotal => _items.fold(0.0, (s, i) => s + i.amount);
  double get _taxAmt => _subtotal * ((double.tryParse(_taxCtrl.text) ?? 0) / 100);
  double get _total => _subtotal + _taxAmt;
  double get _balance => _total - (double.tryParse(_advanceCtrl.text) ?? 0);

  void _openItemDialog({LineItem? item, int? index}) {
    final nameCtrl = TextEditingController(text: item?.name ?? '');
    final qtyCtrl = TextEditingController(text: item != null ? item.quantity.toString() : '1');
    final rateCtrl = TextEditingController(text: item != null ? item.rate.toString() : '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item == null ? 'Add Item' : 'Edit Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Item Name / Size (e.g. Sound System)'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Quantity'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Rate (₹)'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              final newItem = LineItem(
                name: nameCtrl.text.trim(),
                quantity: double.tryParse(qtyCtrl.text) ?? 1,
                rate: double.tryParse(rateCtrl.text) ?? 0,
              );
              setState(() {
                if (index != null) {
                  _items[index] = newItem;
                } else {
                  _items.add(newItem);
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save Item'),
          ),
        ],
      ),
    );
  }

  Future<void> _save({bool sharePdf = false}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add at least 1 item')));
      return;
    }

    final doc = QuotationDoc(
      id: widget.existingDoc?.id,
      docType: _docType,
      docNumber: int.tryParse(_docNumCtrl.text) ?? 1,
      date: _dateCtrl.text.trim(),
      clientName: _clientNameCtrl.text.trim(),
      clientAddress: _clientAddrCtrl.text.trim(),
      eventTitle: _eventTitleCtrl.text.trim(),
      taxPercent: double.tryParse(_taxCtrl.text) ?? 0,
      advancePaid: double.tryParse(_advanceCtrl.text) ?? 0,
      notes: _notesCtrl.text.trim(),
      items: _items,
    );

    if (doc.id == null) {
      await DBHelper.insert(doc);
    } else {
      await DBHelper.update(doc);
    }

    if (sharePdf) {
      final profile = await BusinessProfile.load();
      await PdfService.generateAndShare(doc, profile);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingDoc == null ? 'Create $_docType' : 'Edit $_docType #${_docNumCtrl.text}'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            // Type Toggle
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'QUOTATION', label: Text('QUOTATION'), icon: Icon(Icons.request_quote)),
                ButtonSegment(value: 'INVOICE', label: Text('INVOICE'), icon: Icon(Icons.receipt_long)),
              ],
              selected: {_docType},
              onSelectionChanged: (s) => setState(() => _docType = s.first),
            ),
            const SizedBox(height: 14),

            // Doc Number & Date
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _docNumCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Number (#)', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _dateCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setState(() => _dateCtrl.text = DateFormat('MMM dd, yyyy').format(picked));
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Client Details
            TextFormField(
              controller: _clientNameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Client / Company Name *', border: OutlineInputBorder()),
              validator: (v) => v == null || v.trim().isEmpty ? 'Client name required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _clientAddrCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Client City / Address', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _eventTitleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Event / Venue Title (e.g. 1st R&D Townhall)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Items Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Items List', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                FilledButton.icon(
                  onPressed: () => _openItemDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Item'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Items List
            ..._items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Qty: ${item.quantity}  ×  Rate: ₹${_currency.format(item.rate)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('₹${_currency.format(item.amount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                        onPressed: () => _openItemDialog(item: item, index: idx),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: Colors.red),
                        onPressed: () => setState(() => _items.removeAt(idx)),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 12),
            // Tax & Advance
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _taxCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Tax (%)', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _advanceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Advance Paid (₹)', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Notes
            TextFormField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (Optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),

            // Summary Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  _row('Subtotal', '₹${_currency.format(_subtotal)}'),
                  _row('Tax', '₹${_currency.format(_taxAmt)}'),
                  _row('Total Amount', '₹${_currency.format(_total)}', bold: true),
                  _row('Balance Due', '₹${_currency.format(_balance)}', bold: true, color: const Color(0xFF8B1E24)),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Save Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _save(sharePdf: false),
                    icon: const Icon(Icons.save),
                    label: const Text('Save Only'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _save(sharePdf: true),
                    icon: const Icon(Icons.share),
                    label: const Text('Save & PDF'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8B1E24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v, {bool bold = false, Color? color}) {
    final s = TextStyle(fontSize: bold ? 15 : 13.5, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(k, style: s), Text(v, style: s)]),
    );
  }
}

// ==================== SETTINGS SCREEN (BUSINESS & BANK DETAILS) ====================

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _firmCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _propCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _panCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _accCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await BusinessProfile.load();
    setState(() {
      _firmCtrl.text = p.firmName;
      _tagCtrl.text = p.tagline;
      _propCtrl.text = p.proprietor;
      _phoneCtrl.text = p.phone;
      _cityCtrl.text = p.city;
      _panCtrl.text = p.pan;
      _bankCtrl.text = p.bankName;
      _holderCtrl.text = p.accountHolder;
      _accCtrl.text = p.accountNumber;
      _ifscCtrl.text = p.ifsc;
      _branchCtrl.text = p.branch;
    });
  }

  Future<void> _save() async {
    final p = BusinessProfile(
      firmName: _firmCtrl.text.trim(),
      tagline: _tagCtrl.text.trim(),
      proprietor: _propCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      city: _cityCtrl.text.trim(),
      pan: _panCtrl.text.trim(),
      bankName: _bankCtrl.text.trim(),
      accountHolder: _holderCtrl.text.trim(),
      accountNumber: _accCtrl.text.trim(),
      ifsc: _ifscCtrl.text.trim(),
      branch: _branchCtrl.text.trim(),
    );
    await p.save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings Saved!')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Business & Bank Settings')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text('Firm Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _field(_firmCtrl, 'Firm Name'),
          _field(_tagCtrl, 'Tagline'),
          _field(_propCtrl, 'Proprietor Name'),
          _field(_phoneCtrl, 'Mobile Number'),
          _field(_cityCtrl, 'City / Address'),
          const SizedBox(height: 14),
          const Text('Bank Details (Printed on PDF)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _field(_panCtrl, 'PAN Number'),
          _field(_bankCtrl, 'Bank Name'),
          _field(_holderCtrl, 'Account Holder Name'),
          _field(_accCtrl, 'Account Number'),
          _field(_ifscCtrl, 'IFSC Code'),
          _field(_branchCtrl, 'Branch'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save Settings'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B1E24),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }
}
