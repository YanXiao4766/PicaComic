part of pica_settings;

class HtSettings extends StatefulWidget {
  const HtSettings(this.popUp, {super.key});

  final bool popUp;

  @override
  State<HtSettings> createState() => _HtSettingsState();
}

class _HtSettingsState extends State<HtSettings> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          title: Text("绅士漫画".tl),
        ),
        ListTile(
          leading: const Icon(Icons.dns),
          title: Text("域名".tl),
          subtitle: Text(appdata.settings[31].replaceFirst("https://", "")),
          trailing: IconButton(onPressed: () => changeDomain(context), icon: const Icon(Icons.edit)),
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever),
          title: Text("清除数据".tl),
          subtitle: Text("清除 Cookie 与登录状态".tl),
          onTap: () {
            final baseUrl = appdata.settings[31];
            final cookieJar = SingleInstanceCookieJar.instance!;
            var cookies = cookieJar.loadForRequest(Uri.parse(baseUrl));
            var msg = "${"将清除绅士漫画的所有本地数据".tl}\n"
                "${"Cookie 数量".tl}: ${cookies.length}\n"
                "${"清除后需重新登录".tl}";
            showConfirmDialog(context, "${"确认清除".tl}?", msg, () {
              if (cookies.isNotEmpty) {
                cookieJar.deleteUri(Uri.parse(baseUrl));
              }
              var source = ComicSource.find('htmanga')!;
              source.data['account'] = null;
              source.data['name'] = null;
              source.saveData();
              showToast(message: "已清除绅士漫画数据".tl);
            });
          },
        ),
      ],
    );
  }

  void changeDomain(BuildContext context){
    final FocusNode focusNode = FocusNode();
    var controller = TextEditingController(
      text : appdata.settings[31].replaceFirst("https://", "")
    );

    void onFinished() {
      var text = controller.text;
      if(!text.contains("https://")){
        text = "https://$text";
      }
      App.globalBack();
      if(!text.isURL){
        showToast(message: "Invalid URL");
      }else {
        appdata.settings[31] = text;
        appdata.updateSettings();
        setState(() {});
      }
    }

    showDialog(context: context, builder: (context){
      focusNode.requestFocus();
      return SimpleDialog(
        title: Text("更改域名".tl),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            width: 400,
            child: TextField(
              focusNode: focusNode,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                label: Text("域名".tl)
              ),
              controller: controller,
              onEditingComplete: onFinished,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onFinished, child: Text("完成".tl)),
              const SizedBox(width: 16,),
            ],
          )
        ],
      );
    });
  }
}