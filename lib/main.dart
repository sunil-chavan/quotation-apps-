
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
       
