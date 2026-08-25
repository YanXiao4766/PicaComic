part of pica_settings;

class NhSettings extends StatefulWidget {
  const NhSettings(this.popUp, {super.key});

  final bool popUp;

  @override
  State<NhSettings> createState() => _NhSettingsState();
}

class _NhSettingsState extends State<NhSettings> {

  String baseUrl = "https://nhentai.net";

  void clearData() async {
    final cookieJar = SingleInstanceCookieJar.instance!;
    var cookies = cookieJar.loadForRequest(Uri.parse(baseUrl));
    var title = "${"确认清除".tl}?";
    var msg = "${"将清除 nhentai 的所有本地数据".tl}\n"
        "${"Cookie 数量".tl}: ${cookies.length}\n"
        "${"清除后需重新登录".tl}\n";
    showConfirmDialog(App.globalContext!, title, msg, () {
      NhentaiNetwork().logged = false;
      if (cookies.isNotEmpty) {
        cookieJar.deleteUri(Uri.parse(baseUrl));
      }
      var source = ComicSource.find('nhentai')!;
      source.data["account"] = null;
      source.saveData();
      showToast(message: "已清除 nhentai 数据".tl);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          title: Text("nhentai".tl),
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever),
          title: Text("清除数据".tl),
          subtitle: Text("清除 Cookie 与登录状态".tl),
          onTap: () => clearData(),
        )
      ],
    );
  }
}