import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_scanner_cropper/flutter_scanner_cropper.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:open_file/open_file.dart';
import 'package:openscan/Utilities/Classes.dart';
import 'package:openscan/Utilities/DatabaseHelper.dart';
import 'package:openscan/Utilities/constants.dart';
import 'package:openscan/Utilities/file_operations.dart';
import 'package:openscan/Widgets/Image_Card.dart';
import 'package:openscan/screens/home_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reorderables/reorderables.dart';
import 'package:share_extend/share_extend.dart';

bool enableSelect = false;
bool enableReorder = false;
List<bool> selectedImageIndex = [];

class ViewDocument extends StatefulWidget {
  static String route = "ViewDocument";
  final DirectoryOS directoryOS;
  final bool quickScan;

  ViewDocument({this.quickScan = false, this.directoryOS});

  @override
  _ViewDocumentState createState() => _ViewDocumentState();
}

class _ViewDocumentState extends State<ViewDocument> {
  final GlobalKey<ScaffoldState> scaffoldKey = new GlobalKey<ScaffoldState>();
  DatabaseHelper database = DatabaseHelper();
  List<String> imageFilesPath = [];
  List<Widget> imageCards = [];
  String imageFilePath;
  FileOperations fileOperations;
  String dirPath;
  String fileName = '';
  List<Map<String, dynamic>> directoryData;
  List<ImageOS> directoryImages = [];
  List<ImageOS> initDirectoryImages = [];
  bool enableSelectionIcons = false;
  bool resetReorder = false;
  bool quickScan = false;

  void fileEditCallback({ImageOS imageOS}) {
    bool isFirstImage = false;
    if (imageOS.imgPath == widget.directoryOS.firstImgPath) {
      isFirstImage = true;
    }
    getDirectoryData(
      updateFirstImage: isFirstImage,
      updateIndex: true,
    );
  }

  selectCallback({ImageOS imageOS}) {
    if (selectedImageIndex.contains(true)) {
      setState(() {
        enableSelectionIcons = true;
      });
    } else {
      setState(() {
        enableSelectionIcons = false;
      });
    }
  }

  Future<void> createDirectoryPath() async {
    Directory appDir = await getExternalStorageDirectory();
    dirPath = "${appDir.path}/OpenScan ${DateTime.now()}";
    fileName = dirPath.substring(dirPath.lastIndexOf("/") + 1);
    widget.directoryOS.dirName = fileName;
  }

  Future<dynamic> createImage({bool quickScan}) async {
    File image = await fileOperations.openCamera();
    Directory cacheDir = await getTemporaryDirectory();
    if (image != null) {
      if (!quickScan) {
        imageFilePath = await FlutterScannerCropper.openCrop({
          'src': image.path,
          'dest': cacheDir.path,
        });
      }
      File imageFile = File(imageFilePath ?? image.path);
      setState(() {});
      await fileOperations.saveImage(
        image: imageFile,
        index: directoryImages.length + 1,
        dirPath: dirPath,
      );
      await fileOperations.deleteTemporaryFiles();
      if (quickScan) createImage(quickScan: quickScan);
      getDirectoryData();
    }
  }

  getImageCards() {
    imageCards = [];
    print(selectedImageIndex);
    for (var image in directoryImages) {
      ImageCard imageCard = ImageCard(
        imageOS: image,
        directoryOS: widget.directoryOS,
        fileEditCallback: () {
          fileEditCallback(imageOS: image);
        },
        selectCallback: () {
          selectCallback(imageOS: image);
        },
      );
      if (!imageCards.contains(imageCard)) {
        imageCards.add(imageCard);
      }
    }
    return imageCards;
  }

  void _onReorder(int oldIndex, int newIndex) {
    print(newIndex);
    //TODO: Change index of reordered images
    Widget image = imageCards.removeAt(oldIndex);
    imageCards.insert(newIndex, image);
    ImageOS image1 = directoryImages.removeAt(oldIndex);
    directoryImages.insert(newIndex, image1);
  }

  void getDirectoryData({
    bool updateFirstImage = false,
    bool updateIndex = false,
  }) async {
    directoryImages = [];
    initDirectoryImages = [];
    imageFilesPath = [];
    selectedImageIndex = [];
    int index = 1;
    directoryData = await database.getDirectoryData(widget.directoryOS.dirName);
    print('Directory table[$widget.directoryOS.dirName] => $directoryData');
    for (var image in directoryData) {
      // Updating first image path after delete
      if (updateFirstImage) {
        database.updateFirstImagePath(
            imagePath: image['img_path'], dirPath: widget.directoryOS.dirPath);
        updateFirstImage = false;
      }
      var i = image['idx'];

      // Updating index of images after delete
      if (updateIndex) {
        i = index;
        database.updateImageIndex(
          image: ImageOS(
            idx: i,
            imgPath: image['img_path'],
          ),
          tableName: widget.directoryOS.dirName,
        );
      }

      directoryImages.add(
        ImageOS(
          idx: i,
          imgPath: image['img_path'],
        ),
      );
      initDirectoryImages.add(
        ImageOS(
          idx: i,
          imgPath: image['img_path'],
        ),
      );
      imageFilesPath.add(image['img_path']);
      selectedImageIndex.add(false);
      index += 1;
    }
    print(selectedImageIndex.length);
    setState(() {});
  }

  void handleClick(String value) {
    switch (value) {
      case 'Reorder':
        setState(() {
          enableReorder = true;
        });
        break;
      case 'Select':
        setState(() {
          enableSelect = true;
        });
        break;
      case 'Share':
        showModalBottomSheet(
          context: context,
          builder: _buildBottomSheet,
        );
        break;
    }
  }

  removeSelection() {
    setState(() {
      for (var i = 0; i < selectedImageIndex.length; i++) {
        selectedImageIndex[i] = false;
      }
      enableSelect = false;
    });
  }

  deleteMultipleImages() {
    bool isFirstImage = false;
    for (var i = 0; i < directoryImages.length; i++) {
      if (selectedImageIndex[i]) {
        print('${directoryImages[i].idx}: ${directoryImages[i].imgPath}');
        if (directoryImages[i].imgPath == widget.directoryOS.firstImgPath) {
          isFirstImage = true;
        }

        File(directoryImages[i].imgPath).deleteSync();
        database.deleteImage(
          imgPath: directoryImages[i].imgPath,
          tableName: widget.directoryOS.dirName,
        );
      }
    }
    database.updateImageCount(
      tableName: widget.directoryOS.dirName,
    );
    try {
      Directory(widget.directoryOS.dirPath).deleteSync(recursive: false);
      database.deleteDirectory(dirPath: widget.directoryOS.dirPath);
    } catch (e) {
      getDirectoryData(
        updateFirstImage: isFirstImage,
        updateIndex: true,
      );
    }
    removeSelection();
    Navigator.pop(context);
  }

  // void handleSelectionClick(String value) {
  //   switch (value) {
  //     case 'Delete':
  //       break;
  //     case 'Share':
  //       showModalBottomSheet(
  //         context: context,
  //         builder: _buildBottomSheet,
  //       );
  //       break;
  //   }
  // }

  @override
  void initState() {
    super.initState();
    fileOperations = FileOperations();
    if (widget.directoryOS.dirPath != null) {
      dirPath = widget.directoryOS.dirPath;
      fileName = widget.directoryOS.newName;
      getDirectoryData();
    } else {
      createDirectoryPath();
      quickScan = widget.quickScan;
      createImage(quickScan: quickScan);
    }
  }

  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;
    return SafeArea(
      child: WillPopScope(
        onWillPop: () {
          if (enableSelect || enableReorder) {
            setState(() {
              enableSelect = false;
              removeSelection();
              enableReorder = false;
            });
          } else {
            Navigator.pop(context);
          }
          return;
        },
        child: Scaffold(
          backgroundColor: primaryColor,
          key: scaffoldKey,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: primaryColor,
            leading: (enableSelect || enableReorder)
                ? IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 30,
                    ),
                    onPressed: (enableSelect)
                        ? () {
                            removeSelection();
                          }
                        : () {
                            setState(() {
                              directoryImages = [];
                              for (var image in initDirectoryImages) {
                                directoryImages.add(image);
                              }
                              enableReorder = false;
                            });
                          },
                  )
                : IconButton(
                    icon: Icon(Icons.arrow_back_ios),
                    onPressed: () {
                      Navigator.pop(context, true);
                    },
                  ),
            title: Text(
              fileName,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            actions: (enableReorder)
                ? [
                    GestureDetector(
                      onTap: () {
                        for (var i = 1; i <= directoryImages.length; i++) {
                          directoryImages[i - 1].idx = i;
                          database.updateImagePath(
                            image: directoryImages[i - 1],
                            tableName: widget.directoryOS.dirName,
                          );
                          print('$i: ${directoryImages[i - 1].imgPath}');
                        }
                        setState(() {
                          enableReorder = false;
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.only(right: 10),
                        alignment: Alignment.center,
                        child: Text(
                          'Done',
                          style: TextStyle(color: secondaryColor),
                        ),
                      ),
                    ),
                  ]
                : [
                    (enableSelect)
                        ? IconButton(
                            icon: Icon(
                              Icons.share,
                              color: (enableSelectionIcons)
                                  ? Colors.white
                                  : Colors.grey,
                            ),
                            onPressed: (enableSelectionIcons)
                                ? () {
                                    showModalBottomSheet(
                                      context: context,
                                      builder: _buildBottomSheet,
                                    );
                                  }
                                : () {},
                          )
                        : IconButton(
                            icon: Icon(Icons.picture_as_pdf),
                            onPressed: () async {
                              await fileOperations.saveToAppDirectory(
                                context: context,
                                fileName: fileName,
                                images: directoryImages,
                              );
                              Directory storedDirectory =
                                  await getApplicationDocumentsDirectory();
                              //TODO: Doubt! Is this line needed??
                              // File('${storedDirectory.path}/$fileName.pdf').deleteSync();
                              final result = await OpenFile.open(
                                  '${storedDirectory.path}/$fileName.pdf');

                              setState(() {
                                String _openResult =
                                    "type=${result.type}  message=${result.message}";
                                print(_openResult);
                              });
                            },
                          ),
                    (enableSelect)
                        ? IconButton(
                            icon: Icon(
                              Icons.delete,
                              color: (enableSelectionIcons)
                                  ? Colors.red
                                  : Colors.grey,
                            ),
                            onPressed: (enableSelectionIcons)
                                ? () {
                                    showDialog(
                                      context: context,
                                      builder: (context) {
                                        return AlertDialog(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(10),
                                            ),
                                          ),
                                          title: Text('Delete'),
                                          content: Text(
                                              'Do you really want to delete this file?'),
                                          actions: <Widget>[
                                            FlatButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: Text('Cancel'),
                                            ),
                                            FlatButton(
                                              onPressed: deleteMultipleImages,
                                              child: Text(
                                                'Delete',
                                                style: TextStyle(
                                                    color: Colors.redAccent),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  }
                                : () {},
                          )
                        : PopupMenuButton<String>(
                            onSelected: handleClick,
                            color: primaryColor.withOpacity(0.95),
                            elevation: 30,
                            offset: Offset.fromDirection(20, 20),
                            icon: Icon(Icons.more_vert),
                            itemBuilder: (context) {
                              return [
                                PopupMenuItem(
                                  value: 'Select',
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Select'),
                                      SizedBox(width: 10),
                                      Icon(
                                        Icons.select_all,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'Reorder',
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Reorder'),
                                      SizedBox(width: 10),
                                      Icon(
                                        Icons.reorder,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'Share',
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Share'),
                                      SizedBox(width: 10),
                                      Icon(
                                        Icons.share,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ];
                            },
                          ),
                  ],
          ),
          body: RefreshIndicator(
            backgroundColor: primaryColor,
            color: secondaryColor,
            onRefresh: () async {
              getDirectoryData();
            },
            child: Padding(
              padding: EdgeInsets.all(size.width * 0.01),
              child: Theme(
                data: Theme.of(context).copyWith(accentColor: primaryColor),
                child: ListView(
                  children: [
                    ReorderableWrap(
                      spacing: 10,
                      runSpacing: 10,
                      minMainAxisCount: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: getImageCards(),
                      onReorder: _onReorder,
                      onNoReorder: (int index) {
                        debugPrint(
                            '${DateTime.now().toString().substring(5, 22)} reorder cancelled. index:$index');
                      },
                      onReorderStarted: (int index) {
                        debugPrint(
                            '${DateTime.now().toString().substring(5, 22)} reorder started: index:$index');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          // TODO: Add photos from gallery
          floatingActionButton: SpeedDial(
            marginRight: 18,
            marginBottom: 20,
            animatedIcon: AnimatedIcons.menu_close,
            animatedIconTheme: IconThemeData(size: 22.0),
            visible: true,
            closeManually: false,
            curve: Curves.bounceIn,
            overlayColor: Colors.black,
            overlayOpacity: 0.5,
            tooltip: 'Scan Options',
            heroTag: 'speed-dial-hero-tag',
            backgroundColor: secondaryColor,
            foregroundColor: Colors.black,
            elevation: 8.0,
            shape: CircleBorder(),
            children: [
              SpeedDialChild(
                child: Icon(Icons.camera_alt),
                backgroundColor: Colors.white,
                label: 'Normal Scan',
                labelStyle: TextStyle(fontSize: 18.0, color: Colors.black),
                onTap: () {
                  createImage(quickScan: false);
                },
              ),
              SpeedDialChild(
                child: Icon(Icons.camera_roll),
                backgroundColor: Colors.white,
                label: 'Quick Scan',
                labelStyle: TextStyle(fontSize: 18.0, color: Colors.black),
                onTap: () {
                  createImage(quickScan: true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // removeUnavailableImages() {
  //   if(enableSelect){
  //     for (var image in tempDirectoryImages) {
  //       if (!File(image.imgPath).existsSync()) {
  //         tempImageFilesPath.remove(image.imgPath);
  //         tempDirectoryImages.remove(image);
  //       }
  //     }
  //   }
  // }

  Widget _buildBottomSheet(BuildContext context) {
    FileOperations fileOperations = FileOperations();
    Size size = MediaQuery.of(context).size;
    return Container(
      color: primaryColor,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(15, 20, 15, 15),
            child: Text(
              fileName,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Divider(
            thickness: 0.2,
            indent: 8,
            endIndent: 8,
            color: Colors.white,
          ),
          ListTile(
            leading: Icon(Icons.picture_as_pdf),
            title: Text('Share PDF'),
            onTap: () async {
              List<ImageOS> selectedImages = [];
              for (var image in directoryImages) {
                if (selectedImageIndex.elementAt(image.idx - 1)) {
                  selectedImages.add(image);
                }
              }
              print(selectedImages.length);
              await fileOperations.saveToAppDirectory(
                context: context,
                fileName: fileName,
                images: (enableSelect) ? selectedImages : directoryImages,
              );
              Directory storedDirectory =
                  await getApplicationDocumentsDirectory();
              ShareExtend.share(
                  '${storedDirectory.path}/$fileName.pdf', 'file');
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.phone_android),
            title: Text('Save to device'),
            onTap: () async {
              List<ImageOS> selectedImages = [];
              for (var image in directoryImages) {
                if (selectedImageIndex.elementAt(image.idx - 1)) {
                  selectedImages.add(image);
                }
              }
              String savedDirectory;
              Navigator.pop(context);
              savedDirectory = await fileOperations.saveToDevice(
                context: context,
                fileName: fileName,
                images: (enableSelect) ? selectedImages : directoryImages,
              );
              String displayText;
              (savedDirectory != null)
                  ? displayText = "Saved at $savedDirectory"
                  : displayText = "Failed to generate pdf. Try Again.";
              scaffoldKey.currentState.showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10))),
                  backgroundColor: primaryColor,
                  duration: Duration(seconds: 1),
                  content: Container(
                    decoration: BoxDecoration(),
                    alignment: Alignment.center,
                    height: 20,
                    width: size.width * 0.3,
                    child: Text(
                      displayText,
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.image),
            title: Text('Share images'),
            onTap: () {
              List<String> selectedImagesPath = [];
              for (var image in directoryImages) {
                if (selectedImageIndex.elementAt(image.idx - 1)) {
                  selectedImagesPath.add(image.imgPath);
                }
              }
              ShareExtend.shareMultiple(
                  (enableSelect) ? selectedImagesPath : imageFilesPath, 'file');
              Navigator.pop(context);
            },
          ),
          (enableSelect)
              ? Container()
              : ListTile(
                  leading: Icon(
                    Icons.delete,
                    color: Colors.redAccent,
                  ),
                  title: Text(
                    'Delete All',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(
                              Radius.circular(10),
                            ),
                          ),
                          title: Text('Delete'),
                          content:
                              Text('Do you really want to delete this file?'),
                          actions: <Widget>[
                            FlatButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text('Cancel'),
                            ),
                            FlatButton(
                              onPressed: () {
                                Directory(dirPath).deleteSync(recursive: true);
                                DatabaseHelper()
                                  ..deleteDirectory(dirPath: dirPath);
                                Navigator.popUntil(
                                  context,
                                  ModalRoute.withName(HomeScreen.route),
                                );
                              },
                              child: Text(
                                'Delete',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
        ],
      ),
    );
  }
}
