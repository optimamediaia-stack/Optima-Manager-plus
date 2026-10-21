import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const green = Color(0xFF1B5E20);
const orange = Color(0xFFF28C28);
final money = NumberFormat.currency(locale: 'fr_FR', symbol: 'FCFA', decimalDigits: 0);
final dateFmt = DateFormat('dd/MM/yyyy');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.instance.init();
  runApp(const OptimaManagerApp());
}

class Store {
  Store._();
  static final instance = Store._();
  late Database db;

  Future<void> init() async {
    final path = p.join(await getDatabasesPath(), 'optima_manager.db');
    db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''CREATE TABLE clients(
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT,
        email TEXT, address TEXT, notes TEXT, created_at TEXT NOT NULL)''');
      await db.execute('''CREATE TABLE projects(
        id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, client_id INTEGER,
        category TEXT, status TEXT NOT NULL, budget REAL NOT NULL DEFAULT 0,
        due_date TEXT, notes TEXT, created_at TEXT NOT NULL)''');
      await db.execute('''CREATE TABLE documents(
        id INTEGER PRIMARY KEY AUTOINCREMENT, ref TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL, client_id INTEGER, title TEXT NOT NULL,
        amount REAL NOT NULL, paid REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL, issue_date TEXT NOT NULL, due_date TEXT, notes TEXT)''');
      await db.execute('''CREATE TABLE expenses(
        id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT NOT NULL,
        category TEXT, amount REAL NOT NULL, date TEXT NOT NULL, notes TEXT)''');
      await db.execute('''CREATE TABLE payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT, document_id INTEGER NOT NULL,
        amount REAL NOT NULL, date TEXT NOT NULL, method TEXT, notes TEXT)''');
      await db.execute('''CREATE TABLE settings(
        key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
      await db.insert('settings', {'key':'company_name','value':'OPTIMA MEDIA'});
      await db.insert('settings', {'key':'slogan','value':'Créer autrement'});
      await db.insert('settings', {'key':'tax_rate','value':'0'});
      await db.insert('settings', {'key':'next_ref','value':'1'});
    });
  }

  Future<List<Map<String, Object?>>> all(String table, {String? orderBy}) =>
      db.query(table, orderBy: orderBy ?? 'id DESC');
  Future<int> add(String table, Map<String, Object?> row) => db.insert(table, row);
  Future<int> edit(String table, int id, Map<String, Object?> row) =>
      db.update(table, row, where: 'id=?', whereArgs: [id]);
  Future<int> remove(String table, int id) => db.delete(table, where: 'id=?', whereArgs: [id]);
  Future<double> sum(String table, String field, {String? where, List<Object?>? args}) async {
    final rows = await db.rawQuery('SELECT COALESCE(SUM($field),0) total FROM $table ${where == null ? '' : 'WHERE $where'}', args);
    return (rows.first['total'] as num).toDouble();
  }
  Future<String> nextRef(String prefix) async {
    final key = 'next_ref';
    final row = await db.query('settings', where: 'key=?', whereArgs: [key]);
    final n = int.tryParse(row.firstOrNull?['value']?.toString() ?? '1') ?? 1;
    await db.update('settings', {'value':'${n+1}'}, where:'key=?', whereArgs:[key]);
    return '$prefix-${DateTime.now().year}-${n.toString().padLeft(4,'0')}';
  }
}

extension FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class OptimaManagerApp extends StatelessWidget {
  const OptimaManagerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OPTIMA MANAGER',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: green, primary: green, secondary: orange),
      scaffoldBackgroundColor: const Color(0xFFF6F8F6), appBarTheme: const AppBarTheme(backgroundColor: green, foregroundColor: Colors.white),
      useMaterial3: true, inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder())),
    home: const HomeShell(),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override State<HomeShell> createState() => _HomeShellState();
}
class _HomeShellState extends State<HomeShell> {
  int index = 0;
  final titles = const ['Tableau de bord','Clients','Documents','Finances','Projets','Paramètres'];
  @override Widget build(BuildContext context) {
    final pages = [Dashboard(onGo:(i)=>setState(()=>index=i)), const ClientsPage(), const DocumentsPage(), const FinancePage(), const ProjectsPage(), const SettingsPage()];
    return Scaffold(
      appBar: AppBar(title: Row(children: [ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.asset('assets/branding/optima_media_logo.jpg', width: 34, height: 34, fit: BoxFit.cover)), const SizedBox(width:10), Text(titles[index], style: const TextStyle(fontWeight: FontWeight.w700))])),
      body: IndexedStack(index:index, children:pages),
      bottomNavigationBar: NavigationBar(selectedIndex:index, onDestinationSelected:(i)=>setState(()=>index=i),
        destinations: const [
          NavigationDestination(icon:Icon(Icons.dashboard_outlined),selectedIcon:Icon(Icons.dashboard),label:'Accueil'),
          NavigationDestination(icon:Icon(Icons.people_outline),selectedIcon:Icon(Icons.people),label:'Clients'),
          NavigationDestination(icon:Icon(Icons.description_outlined),selectedIcon:Icon(Icons.description),label:'Documents'),
          NavigationDestination(icon:Icon(Icons.account_balance_wallet_outlined),selectedIcon:Icon(Icons.account_balance_wallet),label:'Finances'),
          NavigationDestination(icon:Icon(Icons.work_outline),selectedIcon:Icon(Icons.work),label:'Projets'),
          NavigationDestination(icon:Icon(Icons.settings_outlined),selectedIcon:Icon(Icons.settings),label:'Réglages'),
        ]),
    );
  }
}

class Dashboard extends StatefulWidget {
  final ValueChanged<int> onGo;
  const Dashboard({super.key, required this.onGo});
  @override State<Dashboard> createState()=>_DashboardState();
}
class _DashboardState extends State<Dashboard> {
  Future<Map<String,Object>> load() async {
    final clients=(await Store.instance.all('clients')).length;
    final docs=await Store.instance.all('documents');
    final projects=(await Store.instance.all('projects')).length;
    final revenue=await Store.instance.sum('payments','amount');
    final expenses=await Store.instance.sum('expenses','amount');
    final due=docs.fold<double>(0,(s,d)=>s+(((d['amount'] as num).toDouble())-((d['paid'] as num).toDouble())));
    return {'clients':clients,'projects':projects,'revenue':revenue,'expenses':expenses,'due':due};
  }
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,Object>>(future:load(),builder:(context,s){
    if(!s.hasData)return const Center(child:CircularProgressIndicator());
    final d=s.data!;
    return ListView(padding:const EdgeInsets.all(16),children:[
      Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(color:green,borderRadius:BorderRadius.circular(20)),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('OPTIMA MANAGER',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.bold)),
          const SizedBox(height:4),const Text('Pilotez votre activité, même hors connexion.',style:TextStyle(color:Colors.white70)),
          const SizedBox(height:18),Wrap(spacing:8,runSpacing:8,children:[
            FilledButton.icon(onPressed:()=>widget.onGo(1),icon:const Icon(Icons.person_add_alt_1),label:const Text('Nouveau client')),
            FilledButton.tonalIcon(onPressed:()=>widget.onGo(2),icon:const Icon(Icons.add),label:const Text('Créer document')),
          ])
        ])),
      const SizedBox(height:18),
      GridView.count(crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisSpacing:10,mainAxisSpacing:10,childAspectRatio:1.35,children:[
        StatCard(label:'Clients',value:'${d['clients']}',icon:Icons.people),
        StatCard(label:'Projets',value:'${d['projects']}',icon:Icons.work),
        StatCard(label:'Encaissements',value:money.format(d['revenue']),icon:Icons.trending_up),
        StatCard(label:'Dépenses',value:money.format(d['expenses']),icon:Icons.trending_down),
      ]),
      const SizedBox(height:12),
      Card(child:ListTile(leading:const Icon(Icons.pending_actions,color:orange),title:const Text('Reste à encaisser'),subtitle:Text(money.format(d['due'])),trailing:const Icon(Icons.chevron_right),onTap:()=>widget.onGo(2))),
      const Padding(padding:EdgeInsets.only(top:12),child:Text('Les indicateurs sont calculés à partir des données enregistrées sur cet appareil.',style:TextStyle(color:Colors.black54,fontSize:12)))
    ]);
  });
}
class StatCard extends StatelessWidget {
  final String label,value; final IconData icon;
  const StatCard({super.key,required this.label,required this.value,required this.icon});
  @override Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
    Icon(icon,color:green),Text(value,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold),maxLines:2,overflow:TextOverflow.ellipsis),Text(label,style:const TextStyle(color:Colors.black54))
  ])));
}

Future<String?> askText(BuildContext context,String title,{String initial='',String hint='',TextInputType keyboard=TextInputType.text,bool required=true}) async {
  final c=TextEditingController(text:initial);
  return showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),content:TextField(controller:c,autofocus:true,keyboardType:keyboard,decoration:InputDecoration(hintText:hint),),actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Annuler')),
    FilledButton(onPressed:()=>Navigator.pop(ctx,c.text.trim()),child:const Text('Enregistrer')),
  ]));
}
Future<void> showInfo(BuildContext context,String msg) => showDialog<void>(context:context,builder:(ctx)=>AlertDialog(content:Text(msg),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Fermer'))]));

class ClientsPage extends StatefulWidget { const ClientsPage({super.key}); @override State<ClientsPage> createState()=>_ClientsPageState(); }
class _ClientsPageState extends State<ClientsPage> {
  String query='';
  Future<void> addClient() async {
    final name=await askText(context,'Nom du client'); if(!mounted||name==null||name.isEmpty)return;
    final phone=await askText(context,'Téléphone',required:false); if(!mounted)return;
    final email=await askText(context,'E-mail (facultatif)',required:false); if(!mounted)return;
    final address=await askText(context,'Adresse (facultatif)',required:false); if(!mounted)return;
    await Store.instance.add('clients',{'name':name,'phone':phone??'','email':email??'','address':address??'','notes':'','created_at':DateTime.now().toIso8601String()});
    setState((){});
  }
  Future<void> editClient(Map<String,Object?> c) async {
    final name=await askText(context,'Nom du client',initial:'${c['name']}'); if(!mounted||name==null||name.isEmpty)return;
    final phone=await askText(context,'Téléphone',initial:'${c['phone']??''}',required:false); if(!mounted)return;
    final email=await askText(context,'E-mail',initial:'${c['email']??''}',required:false); if(!mounted)return;
    final address=await askText(context,'Adresse',initial:'${c['address']??''}',required:false); if(!mounted)return;
    await Store.instance.edit('clients',c['id'] as int,{'name':name,'phone':phone??'','email':email??'','address':address??''}); setState((){});
  }
  @override Widget build(BuildContext context)=>Scaffold(
    body:FutureBuilder<List<Map<String,Object?>>>(future:Store.instance.all('clients',orderBy:'name COLLATE NOCASE'),builder:(ctx,s){
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final list=s.data!.where((c)=>'${c['name']} ${c['phone']} ${c['email']}'.toLowerCase().contains(query.toLowerCase())).toList();
      return Column(children:[
        Padding(padding:const EdgeInsets.all(12),child:TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Rechercher un client'),onChanged:(v)=>setState(()=>query=v))),
        Expanded(child:list.isEmpty?const EmptyState(text:'Aucun client. Appuyez sur + pour ajouter votre premier client.'):ListView.builder(itemCount:list.length,itemBuilder:(ctx,i){
          final c=list[i]; return Card(margin:const EdgeInsets.symmetric(horizontal:12,vertical:4),child:ListTile(leading:CircleAvatar(backgroundColor:green,child:Text('${c['name']}'.isEmpty?'?':'${c['name']}'.substring(0,1).toUpperCase(),style:const TextStyle(color:Colors.white))),title:Text('${c['name']}'),subtitle:Text('${c['phone']??''}${(c['email']??'').toString().isEmpty?'':' • ${c['email']}'}'),onTap:()=>editClient(c),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{final ok=await confirmDelete(context);if(ok){await Store.instance.remove('clients',c['id'] as int);if(context.mounted)setState((){});}})));
        })),
      ]);
    }),
    floatingActionButton:FloatingActionButton.extended(onPressed:addClient,icon:const Icon(Icons.add),label:const Text('Client')));
}

Future<bool> confirmDelete(BuildContext context) async => (await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Confirmer la suppression'),content:const Text('Cette action est définitive.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Supprimer'))])))??false;

class DocumentsPage extends StatefulWidget { const DocumentsPage({super.key}); @override State<DocumentsPage> createState()=>_DocumentsPageState(); }
class _DocumentsPageState extends State<DocumentsPage> {
  Future<void> createDoc(String type) async {
    final title=await askText(context,'Objet du document'); if(!mounted||title==null||title.isEmpty)return;
    final amountStr=await askText(context,'Montant en FCFA',keyboard:TextInputType.number); if(!mounted||amountStr==null)return;
    final amount=double.tryParse(amountStr.replaceAll(' ','').replaceAll(',','.'));
    if(amount==null||amount<0){if(mounted)await showInfo(context,'Montant invalide. Saisissez un nombre positif.');return;}
    final clients=await Store.instance.all('clients',orderBy:'name');
    int? clientId;
    if(clients.isNotEmpty){
      clientId=clients.first['id'] as int;
      if(mounted) await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Client associé'),content:DropdownButtonFormField<int>(value:clientId,items:clients.map((c)=>DropdownMenuItem(value:c['id'] as int,child:Text('${c['name']}',overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>clientId=v),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Continuer'))]));
    }
    if(!mounted)return;
    final ref=await Store.instance.nextRef(type=='Pro forma'?'PF':type=='Facture'?'FAC':'REC');
    await Store.instance.add('documents',{'ref':ref,'type':type,'client_id':clientId,'title':title,'amount':amount,'paid':type=='Reçu'?amount:0,'status':type=='Reçu'?'Payé':'En attente','issue_date':DateTime.now().toIso8601String(),'due_date':null,'notes':''});
    if(type=='Reçu'){
      final id=(await Store.instance.db.query('documents',where:'ref=?',whereArgs:[ref])).first['id'] as int;
      await Store.instance.add('payments',{'document_id':id,'amount':amount,'date':DateTime.now().toIso8601String(),'method':'Non précisé','notes':'Reçu créé'});
    }
    if(mounted){setState((){}); await showInfo(context,'Document $ref créé. Ouvrez-le pour générer son PDF.');}
  }
  Future<void> pdfDoc(Map<String,Object?> d) async {
    final clients=await Store.instance.all('clients');
    final c=clients.where((x)=>x['id']==d['client_id']).firstOrNull;
    final doc=pw.Document();
    doc.addPage(pw.Page(pageFormat:PdfPageFormat.a4,build:(ctx)=>pw.Padding(padding:const pw.EdgeInsets.all(28),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
      pw.Text('OPTIMA MEDIA',style:pw.TextStyle(fontSize:24,fontWeight:pw.FontWeight.bold,color:PdfColor.fromHex('#1B5E20'))),
      pw.Text('Créer autrement'),pw.SizedBox(height:26),
      pw.Text('${d['type']}'.toUpperCase(),style:pw.TextStyle(fontSize:19,fontWeight:pw.FontWeight.bold)),
      pw.Text('Référence : ${d['ref']}'),pw.Text('Date : ${dateFmt.format(DateTime.parse('${d['issue_date']}'))}'),
      pw.SizedBox(height:20),pw.Text('Client : ${c?['name']??'Client non renseigné'}'),
      if((c?['phone']??'').toString().isNotEmpty)pw.Text('Téléphone : ${c?['phone']}'),
      pw.SizedBox(height:24),pw.Text('Objet : ${d['title']}'),
      pw.SizedBox(height:18),pw.Divider(),
      pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Text('Montant total',style:pw.TextStyle(fontSize:15,fontWeight:pw.FontWeight.bold)),pw.Text(money.format(d['amount']),style:pw.TextStyle(fontSize:15,fontWeight:pw.FontWeight.bold))]),
      pw.SizedBox(height:8),pw.Text('Montant payé : ${money.format(d['paid'])}'),
      pw.Text('Reste à payer : ${money.format((d['amount'] as num).toDouble()-(d['paid'] as num).toDouble())}'),
      pw.Spacer(),pw.Divider(),pw.Text('OPTIMA MEDIA — Document généré par OPTIMA MANAGER',style:const pw.TextStyle(fontSize:9)),
    ]))));
    await Printing.layoutPdf(onLayout:(format)=>doc.save(),name:'${d['ref']}.pdf');
  }
  Future<void> pay(Map<String,Object?> d) async {
    final raw=await askText(context,'Montant encaissé (FCFA)',keyboard:TextInputType.number); if(!mounted||raw==null)return;
    final amount=double.tryParse(raw.replaceAll(' ','').replaceAll(',','.'));
    final remaining=(d['amount'] as num).toDouble()-(d['paid'] as num).toDouble();
    if(amount==null||amount<=0||amount>remaining){if(mounted)await showInfo(context,'Montant invalide. Le paiement doit être positif et ne pas dépasser le solde.');return;}
    final method=await askText(context,'Mode de paiement',initial:'Espèces'); if(!mounted)return;
    final paid=(d['paid'] as num).toDouble()+amount;
    await Store.instance.db.transaction((txn)async{
      await txn.insert('payments',{'document_id':d['id'],'amount':amount,'date':DateTime.now().toIso8601String(),'method':method??'Non précisé','notes':''});
      await txn.update('documents',{'paid':paid,'status':paid >= (d['amount'] as num).toDouble()?'Payé':'Partiellement payé'},where:'id=?',whereArgs:[d['id']]);
      if(paid >= (d['amount'] as num).toDouble()){
        final ref=await Store.instance.nextRef('REC');
        await txn.insert('documents',{'ref':ref,'type':'Reçu','client_id':d['client_id'],'title':'Paiement de ${d['ref']}','amount':amount,'paid':amount,'status':'Payé','issue_date':DateTime.now().toIso8601String(),'notes':'Paiement reçu'});
      }
    });
    if(mounted)setState((){});
  }
  @override Widget build(BuildContext context)=>Scaffold(
    body:FutureBuilder<List<Map<String,Object?>>>(future:Store.instance.all('documents'),builder:(ctx,s){
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      if(s.data!.isEmpty)return const EmptyState(text:'Aucun document. Créez un pro forma, une facture ou un reçu.');
      return ListView(children:s.data!.map((d)=>Card(margin:const EdgeInsets.symmetric(horizontal:12,vertical:5),child:ListTile(
        leading:Icon(d['type']=='Facture'?Icons.receipt_long:d['type']=='Reçu'?Icons.verified_outlined:Icons.description,color:green),
        title:Text('${d['title']}',maxLines:2,overflow:TextOverflow.ellipsis),subtitle:Text('${d['ref']} • ${d['type']} • ${d['status']}\n${money.format(d['amount'])}',maxLines:2),
        isThreeLine:true,onTap:()=>pdfDoc(d),trailing:PopupMenuButton<String>(onSelected:(v){if(v=='pdf')pdfDoc(d);if(v=='pay')pay(d);},itemBuilder:(ctx)=>[const PopupMenuItem(value:'pdf',child:Text('Générer / imprimer PDF')),if(d['type']!='Reçu'&&(d['amount'] as num)>(d['paid'] as num))const PopupMenuItem(value:'pay',child:Text('Enregistrer un paiement'))])))).toList());
    }),
    floatingActionButton:PopupMenuButton<String>(tooltip:'Créer un document',icon:const Icon(Icons.add),onSelected:createDoc,itemBuilder:(ctx)=>const [
      PopupMenuItem(value:'Pro forma',child:Text('Nouveau pro forma')),
      PopupMenuItem(value:'Facture',child:Text('Nouvelle facture')),
      PopupMenuItem(value:'Reçu',child:Text('Nouveau reçu de paiement')),
    ]));
}

class FinancePage extends StatefulWidget { const FinancePage({super.key}); @override State<FinancePage> createState()=>_FinancePageState(); }
class _FinancePageState extends State<FinancePage> {
  Future<void> addExpense() async {
    final label=await askText(context,'Libellé de la dépense'); if(!mounted||label==null||label.isEmpty)return;
    final raw=await askText(context,'Montant en FCFA',keyboard:TextInputType.number); if(!mounted||raw==null)return;
    final amount=double.tryParse(raw.replaceAll(' ','').replaceAll(',','.'));
    if(amount==null||amount<=0){if(mounted)await showInfo(context,'Montant invalide.');return;}
    final cat=await askText(context,'Catégorie',initial:'Fonctionnement'); if(!mounted)return;
    await Store.instance.add('expenses',{'label':label,'category':cat??'Autre','amount':amount,'date':DateTime.now().toIso8601String(),'notes':''}); setState((){});
  }
  @override Widget build(BuildContext context)=>Scaffold(
    body:FutureBuilder<List<Map<String,Object?>>>(future:Store.instance.all('expenses'),builder:(ctx,s){
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      return Column(children:[
        FutureBuilder<List<double>>(future:Future.wait([Store.instance.sum('payments','amount'),Store.instance.sum('expenses','amount')]),builder:(ctx,tot)=>Padding(padding:const EdgeInsets.all(12),child:Row(children:[
          Expanded(child:StatCard(label:'Encaissements',value:money.format(tot.data?.first??0),icon:Icons.south_west)),
          Expanded(child:StatCard(label:'Dépenses',value:money.format(tot.data?.last??0),icon:Icons.north_east)),
        ]))),
        Expanded(child:s.data!.isEmpty?const EmptyState(text:'Aucune dépense enregistrée.'):ListView(children:s.data!.map((e)=>Card(margin:const EdgeInsets.symmetric(horizontal:12,vertical:4),child:ListTile(leading:const Icon(Icons.payments_outlined,color:orange),title:Text('${e['label']}'),subtitle:Text('${e['category']} • ${dateFmt.format(DateTime.parse('${e['date']}'))}'),trailing:Text(money.format(e['amount']))))).toList()))
      ]);
    }),
    floatingActionButton:FloatingActionButton.extended(onPressed:addExpense,icon:const Icon(Icons.add),label:const Text('Dépense')));
}

class ProjectsPage extends StatefulWidget { const ProjectsPage({super.key}); @override State<ProjectsPage> createState()=>_ProjectsPageState(); }
class _ProjectsPageState extends State<ProjectsPage> {
  Future<void> addProject() async {
    final title=await askText(context,'Nom du projet'); if(!mounted||title==null||title.isEmpty)return;
    final category=await askText(context,'Type de prestation',initial:'Affiche / Vidéo / Logo'); if(!mounted)return;
    final budgetRaw=await askText(context,'Budget prévu (FCFA)',initial:'0',keyboard:TextInputType.number); if(!mounted||budgetRaw==null)return;
    final budget=double.tryParse(budgetRaw.replaceAll(' ','').replaceAll(',','.'))??0;
    await Store.instance.add('projects',{'title':title,'client_id':null,'category':category??'Autre','status':'En cours','budget':budget,'due_date':null,'notes':'','created_at':DateTime.now().toIso8601String()});setState((){});
  }
  @override Widget build(BuildContext context)=>Scaffold(
    body:FutureBuilder<List<Map<String,Object?>>>(future:Store.instance.all('projects'),builder:(ctx,s){
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      if(s.data!.isEmpty)return const EmptyState(text:'Aucun projet. Ajoutez une prestation ou une commande client.');
      return ListView(children:s.data!.map((p)=>Card(margin:const EdgeInsets.symmetric(horizontal:12,vertical:4),child:ListTile(leading:const Icon(Icons.work_outline,color:green),title:Text('${p['title']}'),subtitle:Text('${p['category']} • ${p['status']}'),trailing:PopupMenuButton<String>(onSelected:(v)async{if(v=='done')await Store.instance.edit('projects',p['id'] as int,{'status':'Terminé'});if(v=='delete'){if(await confirmDelete(context))await Store.instance.remove('projects',p['id'] as int);}if(mounted)setState((){});},itemBuilder:(ctx)=>const [PopupMenuItem(value:'done',child:Text('Marquer terminé')),PopupMenuItem(value:'delete',child:Text('Supprimer'))])))).toList());
    }),
    floatingActionButton:FloatingActionButton.extended(onPressed:addProject,icon:const Icon(Icons.add),label:const Text('Projet')));
}

class SettingsPage extends StatefulWidget { const SettingsPage({super.key}); @override State<SettingsPage> createState()=>_SettingsPageState(); }
class _SettingsPageState extends State<SettingsPage> {
  String tax='0';
  @override void initState(){super.initState();Store.instance.db.query('settings',where:'key=?',whereArgs:['tax_rate']).then((r){if(mounted&&r.isNotEmpty)setState(()=>tax='${r.first['value']}');});}
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(12),children:[
    Card(child:Column(children:[
      const ListTile(leading:Icon(Icons.business,color:green),title:Text('OPTIMA MEDIA'),subtitle:Text('Créer autrement')),
      const Divider(height:1),
      ListTile(leading:const Icon(Icons.percent),title:const Text('Taux de taxe par défaut'),subtitle:Text('$tax %'),trailing:const Icon(Icons.edit),onTap:()async{final v=await askText(context,'Taux de taxe (%)',initial:tax,keyboard:const TextInputType.numberWithOptions(decimal:true));if(v==null)return;final n=double.tryParse(v.replaceAll(',','.'));if(n==null||n<0||n>100){if(context.mounted)await showInfo(context,'Taux invalide (0 à 100).');return;}await Store.instance.db.update('settings',{'value':'$n'},where:'key=?',whereArgs:['tax_rate']);if(mounted)setState(()=>tax='$n');}),
      const ListTile(leading:Icon(Icons.currency_exchange),title:Text('Devise'),subtitle:Text('Franc CFA BCEAO (XOF)')),
      const ListTile(leading:Icon(Icons.cloud_outlined),title:Text('Sauvegarde distante'),subtitle:Text('Prévue dans une prochaine version. Les données actuelles restent sur cet appareil.')),
      const ListTile(leading:Icon(Icons.wifi_off),title:Text('Mode hors connexion'),subtitle:Text('Clients, projets, documents et dépenses sont enregistrés localement.')),
    ])),
    Card(child:ListTile(leading:const Icon(Icons.info_outline),title:const Text('À propos'),subtitle:const Text('OPTIMA MANAGER • Version 1.0.0 • Gestion interne d’Optima Media'))),
    FilledButton.tonalIcon(onPressed:()async{final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Réinitialiser les données ?'),content:const Text('Cette action effacera clients, projets, documents, paiements et dépenses de cet appareil.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Effacer tout'))]));if(ok==true){await Store.instance.db.transaction((txn)async{for(final t in ['payments','documents','expenses','projects','clients']){await txn.delete(t);}});if(context.mounted)await showInfo(context,'Données locales effacées.');}},icon:const Icon(Icons.delete_forever),label:const Text('Réinitialiser les données locales')),
    const Padding(padding:EdgeInsets.all(12),child:Text('Important : effectuez régulièrement une sauvegarde de votre téléphone. La synchronisation cloud n’est pas encore activée.',style:TextStyle(color:Colors.black54,fontSize:12)))
  ]);
}

class EmptyState extends StatelessWidget {
  final String text;
  const EmptyState({super.key,required this.text});
  @override Widget build(BuildContext context)=>Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.inbox_outlined,size:52,color:green),const SizedBox(height:12),Text(text,textAlign:TextAlign.center,style:const TextStyle(color:Colors.black54))])));
}
