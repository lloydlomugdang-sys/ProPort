import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../constants/app_colors.dart';

// Dialogs
import 'editor_dialogs/alignment_dialog.dart';
import 'editor_dialogs/color_picker_dialog.dart';
import 'editor_dialogs/edit_text_dialog.dart';
import 'editor_dialogs/element_options_dialog.dart';
import 'editor_dialogs/font_style_dialog.dart';
import 'editor_dialogs/portfolio_templates_dialog.dart';
import 'editor_dialogs/save_portfolio_dialog.dart';
import 'editor_dialogs/shape_picker_dialog.dart';
import 'editor_dialogs/uploads_panel_dialog.dart';

// Logic
import 'editor_logic/clipboard_logic.dart';
import 'editor_logic/element_layer_logic.dart';
import 'editor_logic/image_element_logic.dart';
import 'editor_logic/portfolio_template_logic.dart';
import 'editor_logic/shape_element_logic.dart';
import 'editor_logic/text_element_logic.dart';

// Widgets
import 'editor_widgets/editor_bottom_toolbar.dart';
import 'editor_widgets/editor_canvas.dart';
import 'editor_widgets/editor_page_section.dart';
import 'editor_widgets/editor_top_bar.dart';
import 'editor_widgets/image_element_actions.dart';
import 'editor_widgets/shape_element_actions.dart';
import 'editor_widgets/text_element_actions.dart';

// Models
import 'models/portfolio_image_element.dart';
import 'models/portfolio_page_data.dart';
import 'models/portfolio_save_result.dart';
import 'models/portfolio_shape_element.dart';
import 'models/portfolio_text_element.dart';

enum PortfolioCanvasType {
  a4Portrait,
  a4Landscape,
  square,
}

class PortfolioEditorScreen extends StatefulWidget {
  final PortfolioCanvasType canvasType;
  final String initialTitle;
  final List<PortfolioPageData> initialPages;
  final List<String> initialUploadedImagePaths;

  const PortfolioEditorScreen({
    super.key,
    required this.canvasType,
    this.initialTitle = 'Untitled Portfolio',
    this.initialPages = const [],
    this.initialUploadedImagePaths = const [],
  });

  @override
  State<PortfolioEditorScreen> createState() => _PortfolioEditorScreenState();
}

class _PortfolioEditorScreenState extends State<PortfolioEditorScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  late String portfolioTitle;

  int selectedToolIndex = -1;
  int selectedPageIndex = 0;
  int nextPageId = 2;

  int? selectedTextElementId;
  int? selectedShapeElementId;
  int? selectedImageElementId;

  int nextTextElementId = 1;
  int nextShapeElementId = 1;
  int nextImageElementId = 1;

  int nextFrontZIndex = 1;
  int nextBackZIndex = 0;

  PortfolioTextElement? copiedTextElement;
  PortfolioShapeElement? copiedShapeElement;
  PortfolioImageElement? copiedImageElement;

  List<PortfolioTextElement> textElements = [];
  List<PortfolioShapeElement> shapeElements = [];
  List<PortfolioImageElement> imageElements = [];

  List<PortfolioPageData> pages = [];
  final List<String> uploadedImagePaths = [];

  @override
  void initState() {
    super.initState();

    portfolioTitle = widget.initialTitle;
    uploadedImagePaths.addAll(widget.initialUploadedImagePaths);

    if (widget.initialPages.isNotEmpty) {
      pages = widget.initialPages
          .map((page) => page.deepCopy())
          .toList();
    } else {
  pages = [
    const PortfolioPageData(
      id: 1,
      textElements: [],
      shapeElements: [],
      imageElements: [],
    ),
  ];
}

    selectedPageIndex = 0;
    nextPageId = _getNextPageId();

    _loadPageToEditor(selectedPageIndex);
  }

  int _getNextPageId() {
    int highestId = 0;

    for (final page in pages) {
      if (page.id > highestId) {
        highestId = page.id;
      }
    }

    return highestId + 1;
  }

  void _saveCurrentPageState() {
    if (pages.isEmpty || selectedPageIndex >= pages.length) {
      return;
    }

    pages[selectedPageIndex] = pages[selectedPageIndex].copyWith(
      textElements: textElements
          .map((element) => element.copyWith())
          .toList(),
      shapeElements: shapeElements
          .map((element) => element.copyWith())
          .toList(),
      imageElements: imageElements
          .map((element) => element.copyWith())
          .toList(),
    );
  }

  void _loadPageToEditor(int pageIndex) {
    final page = pages[pageIndex];

    textElements = page.textElements
        .map((element) => element.copyWith())
        .toList();

    shapeElements = page.shapeElements
        .map((element) => element.copyWith())
        .toList();

    imageElements = page.imageElements
        .map((element) => element.copyWith())
        .toList();

    selectedTextElementId = null;
    selectedShapeElementId = null;
    selectedImageElementId = null;
    selectedToolIndex = -1;

    nextTextElementId = _getNextTextElementId();
    nextShapeElementId = _getNextShapeElementId();
    nextImageElementId = _getNextImageElementId();

    nextFrontZIndex = _getNextFrontZIndex();
    nextBackZIndex = _getNextBackZIndex();
  }

  int _getNextTextElementId() {
    if (textElements.isEmpty) return 1;

    int highestId = 0;

    for (final element in textElements) {
      if (element.id > highestId) {
        highestId = element.id;
      }
    }

    return highestId + 1;
  }

  int _getNextShapeElementId() {
    if (shapeElements.isEmpty) return 1;

    int highestId = 0;

    for (final element in shapeElements) {
      if (element.id > highestId) {
        highestId = element.id;
      }
    }

    return highestId + 1;
  }

  int _getNextImageElementId() {
    if (imageElements.isEmpty) return 1;

    int highestId = 0;

    for (final element in imageElements) {
      if (element.id > highestId) {
        highestId = element.id;
      }
    }

    return highestId + 1;
  }

  int _getNextFrontZIndex() {
    int highestZIndex = 0;

    for (final element in textElements) {
      if (element.zIndex > highestZIndex) {
        highestZIndex = element.zIndex;
      }
    }

    for (final element in shapeElements) {
      if (element.zIndex > highestZIndex) {
        highestZIndex = element.zIndex;
      }
    }

    for (final element in imageElements) {
      if (element.zIndex > highestZIndex) {
        highestZIndex = element.zIndex;
      }
    }

    return highestZIndex + 1;
  }

  int _getNextBackZIndex() {
    int lowestZIndex = 0;

    for (final element in textElements) {
      if (element.zIndex < lowestZIndex) {
        lowestZIndex = element.zIndex;
      }
    }

    for (final element in shapeElements) {
      if (element.zIndex < lowestZIndex) {
        lowestZIndex = element.zIndex;
      }
    }

    for (final element in imageElements) {
      if (element.zIndex < lowestZIndex) {
        lowestZIndex = element.zIndex;
      }
    }

    return lowestZIndex - 1;
  }

  String get canvasLabel {
    switch (widget.canvasType) {
      case PortfolioCanvasType.a4Portrait:
        return 'A4 Portrait';
      case PortfolioCanvasType.a4Landscape:
        return 'A4 Landscape';
      case PortfolioCanvasType.square:
        return 'Square';
    }
  }

  String get canvasMeasurement {
    switch (widget.canvasType) {
      case PortfolioCanvasType.a4Portrait:
        return '210 × 297 mm';
      case PortfolioCanvasType.a4Landscape:
        return '297 × 210 mm';
      case PortfolioCanvasType.square:
        return '1080 × 1080 px';
    }
  }

  double get canvasWidth {
    switch (widget.canvasType) {
      case PortfolioCanvasType.a4Portrait:
        return 225;
      case PortfolioCanvasType.a4Landscape:
        return 300;
      case PortfolioCanvasType.square:
        return 245;
    }
  }

  double get canvasHeight {
    switch (widget.canvasType) {
      case PortfolioCanvasType.a4Portrait:
        return 318;
      case PortfolioCanvasType.a4Landscape:
        return 212;
      case PortfolioCanvasType.square:
        return 245;
    }
  }

  PortfolioTextElement? get selectedTextElement {
    if (selectedTextElementId == null) return null;

    for (final element in textElements) {
      if (element.id == selectedTextElementId) {
        return element;
      }
    }

    return null;
  }

  PortfolioShapeElement? get selectedShapeElement {
    if (selectedShapeElementId == null) return null;

    for (final element in shapeElements) {
      if (element.id == selectedShapeElementId) {
        return element;
      }
    }

    return null;
  }

  PortfolioImageElement? get selectedImageElement {
    if (selectedImageElementId == null) return null;

    for (final element in imageElements) {
      if (element.id == selectedImageElementId) {
        return element;
      }
    }

    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  Future<void> _savePortfolio() async {
    _saveCurrentPageState();

    final savedTitle = await showSavePortfolioDialog(
      context: context,
      initialTitle: portfolioTitle,
    );

    if (savedTitle == null) return;

    setState(() {
      portfolioTitle = savedTitle;
    });

    if (!mounted) return;

    Navigator.pop(
      context,
      PortfolioSaveResult(
        title: savedTitle,
        sizeLabel: canvasLabel,
        pages: pages
            .map((page) => page.deepCopy())
            .toList(),
        uploadedImagePaths: List<String>.from(uploadedImagePaths),
      ),
    );
  }

  void _selectPage(int pageIndex) {
    if (pageIndex == selectedPageIndex) return;

    setState(() {
      _saveCurrentPageState();
      selectedPageIndex = pageIndex;
      _loadPageToEditor(pageIndex);
    });
  }

  void _addNewPage() {
    setState(() {
      _saveCurrentPageState();

      pages.add(
        PortfolioPageData(
          id: nextPageId,
          textElements: const [],
          shapeElements: const [],
          imageElements: const [],
        ),
      );

      nextPageId++;
      selectedPageIndex = pages.length - 1;
      _loadPageToEditor(selectedPageIndex);
    });

    _showMessage('New portfolio section added.');
  }

  void _addTextElement() {
    final newElement = TextElementLogic.createTextElement(
      id: nextTextElementId,
      zIndex: nextFrontZIndex,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );

    setState(() {
      textElements.add(newElement);
      selectedTextElementId = newElement.id;
      selectedShapeElementId = null;
      selectedImageElementId = null;
      selectedToolIndex = 0;

      nextTextElementId++;
      nextFrontZIndex++;
    });
  }

  Future<void> _showShapePicker() async {
    final selectedShape = await showShapePickerDialog(context);

    if (selectedShape == null) return;

    _addShapeElement(selectedShape);
  }

  void _addShapeElement(PortfolioShapeType shapeType) {
    final newShape = ShapeElementLogic.createShapeElement(
      id: nextShapeElementId,
      zIndex: nextFrontZIndex,
      shapeType: shapeType,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );

    setState(() {
      shapeElements.add(newShape);
      selectedShapeElementId = newShape.id;
      selectedTextElementId = null;
      selectedImageElementId = null;
      selectedToolIndex = 1;

      nextShapeElementId++;
      nextFrontZIndex++;
    });
  }

  Future<void> _pickImageFromCameraRoll() async {
    try {
      final XFile? pickedImage = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (!mounted) return;

      if (pickedImage == null) {
        _showMessage('No image selected.');
        return;
      }

      _addImageElement(pickedImage.path);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Unable to open camera roll.');
    }
  }

  Future<void> _openUploadsPanel() async {
    final selectedUpload = await showUploadsPanelDialog(
      context: context,
      uploadedImagePaths: uploadedImagePaths,
    );

    if (selectedUpload == null) return;

    if (selectedUpload == uploadNewImageAction) {
      await _pickUploadImageFromGallery();
      return;
    }

    _addImageElement(selectedUpload);
  }

  Future<void> _pickUploadImageFromGallery() async {
    try {
      final XFile? pickedImage = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (!mounted) return;

      if (pickedImage == null) {
        _showMessage('No image uploaded.');
        return;
      }

      setState(() {
        if (!uploadedImagePaths.contains(pickedImage.path)) {
          uploadedImagePaths.insert(0, pickedImage.path);
        }
      });

      _addImageElement(pickedImage.path);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Unable to upload image.');
    }
  }

  void _addImageElement(String imagePath) {
    final newImage = ImageElementLogic.createImageElement(
      id: nextImageElementId,
      zIndex: nextFrontZIndex,
      imagePath: imagePath,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );

    setState(() {
      imageElements.add(newImage);
      selectedImageElementId = newImage.id;
      selectedTextElementId = null;
      selectedShapeElementId = null;

      nextImageElementId++;
      nextFrontZIndex++;
    });

    _showMessage('Image added to canvas.');
  }

  Future<void> _openPortfoliosPanel() async {
    final selectedTemplate = await showPortfolioTemplatesDialog(context);

    if (selectedTemplate == null) return;

    final bool hasCurrentDesign =
        textElements.isNotEmpty ||
        shapeElements.isNotEmpty ||
        imageElements.isNotEmpty;

    if (hasCurrentDesign) {
      final shouldReplace = await _confirmReplaceCurrentDesign();

      if (!shouldReplace) return;
    }

    _applyPortfolioTemplate(selectedTemplate);
  }

  Future<bool> _confirmReplaceCurrentDesign() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Replace Current Design?',
            style: TextStyle(
              color: AppColors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Applying a portfolio layout will replace the current elements on this page.',
            style: TextStyle(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.input,
                foregroundColor: AppColors.white,
              ),
              child: const Text('Replace'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _applyPortfolioTemplate(PortfolioTemplateType templateType) {
    final template = PortfolioTemplateLogic.buildTemplate(
      type: templateType,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );

    setState(() {
      textElements = template.textElements;
      shapeElements = template.shapeElements;
      imageElements = [];

      selectedTextElementId = null;
      selectedShapeElementId = null;
      selectedImageElementId = null;

      nextTextElementId = template.nextTextElementId;
      nextShapeElementId = template.nextShapeElementId;
      nextImageElementId = 1;

      nextFrontZIndex = template.nextFrontZIndex;
      nextBackZIndex = 0;

      copiedTextElement = null;
      copiedShapeElement = null;
      copiedImageElement = null;
    });

    if (templateType == PortfolioTemplateType.blank) {
      _showMessage('Blank portfolio page ready.');
    } else {
      _showMessage('Portfolio layout applied to current page.');
    }
  }

  void _selectTextElement(int elementId) {
    setState(() {
      selectedTextElementId = elementId;
      selectedShapeElementId = null;
      selectedImageElementId = null;
    });
  }

  void _selectShapeElement(int elementId) {
    setState(() {
      selectedShapeElementId = elementId;
      selectedTextElementId = null;
      selectedImageElementId = null;
    });
  }

  void _selectImageElement(int elementId) {
    setState(() {
      selectedImageElementId = elementId;
      selectedTextElementId = null;
      selectedShapeElementId = null;
    });
  }

  void _unselectElements() {
    setState(() {
      selectedTextElementId = null;
      selectedShapeElementId = null;
      selectedImageElementId = null;
    });
  }

  void _moveTextElement(int elementId, Offset newPosition) {
    setState(() {
      textElements = TextElementLogic.updatePosition(
        elements: textElements,
        elementId: elementId,
        newPosition: newPosition,
      );
    });
  }

  void _resizeTextElement(int elementId, Size newSize) {
    setState(() {
      textElements = TextElementLogic.updateSize(
        elements: textElements,
        elementId: elementId,
        newSize: newSize,
      );
    });
  }

  void _moveShapeElement(int elementId, Offset newPosition) {
    setState(() {
      shapeElements = ShapeElementLogic.updatePosition(
        elements: shapeElements,
        elementId: elementId,
        newPosition: newPosition,
      );
    });
  }

  void _resizeShapeElement(int elementId, Size newSize) {
    setState(() {
      shapeElements = ShapeElementLogic.updateSize(
        elements: shapeElements,
        elementId: elementId,
        newSize: newSize,
      );
    });
  }

  void _moveImageElement(int elementId, Offset newPosition) {
    setState(() {
      imageElements = ImageElementLogic.updatePosition(
        elements: imageElements,
        elementId: elementId,
        newPosition: newPosition,
      );
    });
  }

  void _resizeImageElement(int elementId, Size newSize) {
    setState(() {
      imageElements = ImageElementLogic.updateSize(
        elements: imageElements,
        elementId: elementId,
        newSize: newSize,
      );
    });
  }

  Future<void> _editSelectedText() async {
    final element = selectedTextElement;

    if (element == null) return;

    final updatedText = await showEditTextDialog(
      context: context,
      initialText: element.text,
    );

    if (updatedText == null) return;

    setState(() {
      textElements = TextElementLogic.updateText(
        elements: textElements,
        elementId: element.id,
        newText: updatedText,
      );
    });
  }

  Future<void> _pickSelectedTextColor() async {
    final element = selectedTextElement;

    if (element == null) return;

    final color = await showColorPickerDialog(
      context: context,
      title: 'Choose Text Color',
      currentColor: element.color,
    );

    if (color == null) return;

    setState(() {
      textElements = TextElementLogic.updateColor(
        elements: textElements,
        elementId: element.id,
        color: color,
      );
    });
  }

  Future<void> _pickSelectedFontStyle() async {
    final element = selectedTextElement;

    if (element == null) return;

    final selectedFontFamily = await showFontStyleDialog(
      context: context,
      currentFontFamily: element.fontFamily,
    );

    if (selectedFontFamily == null) return;

    setState(() {
      textElements = TextElementLogic.updateFontFamily(
        elements: textElements,
        elementId: element.id,
        fontFamily: selectedFontFamily,
      );
    });
  }

  Future<void> _pickSelectedShapeColor() async {
    final element = selectedShapeElement;

    if (element == null) return;

    final color = await showColorPickerDialog(
      context: context,
      title: 'Choose Shape Color',
      currentColor: element.color,
    );

    if (color == null) return;

    setState(() {
      shapeElements = ShapeElementLogic.updateColor(
        elements: shapeElements,
        elementId: element.id,
        color: color,
      );
    });
  }

  void _decreaseSelectedFontSize() {
    final element = selectedTextElement;

    if (element == null) return;

    setState(() {
      textElements = TextElementLogic.decreaseFontSize(
        elements: textElements,
        elementId: element.id,
      );
    });
  }

  void _increaseSelectedFontSize() {
    final element = selectedTextElement;

    if (element == null) return;

    setState(() {
      textElements = TextElementLogic.increaseFontSize(
        elements: textElements,
        elementId: element.id,
      );
    });
  }

  void _toggleSelectedBold() {
    final element = selectedTextElement;

    if (element == null) return;

    setState(() {
      textElements = TextElementLogic.toggleBold(
        elements: textElements,
        elementId: element.id,
      );
    });
  }

  void _toggleSelectedItalic() {
    final element = selectedTextElement;

    if (element == null) return;

    setState(() {
      textElements = TextElementLogic.toggleItalic(
        elements: textElements,
        elementId: element.id,
      );
    });
  }

  void _toggleSelectedUnderline() {
    final element = selectedTextElement;

    if (element == null) return;

    setState(() {
      textElements = TextElementLogic.toggleUnderline(
        elements: textElements,
        elementId: element.id,
      );
    });
  }

  void _alignSelectedTextLeft() {
    final element = selectedTextElement;

    if (element == null) return;

    setState(() {
      textElements = TextElementLogic.setAlignment(
        elements: textElements,
        elementId: element.id,
        alignment: TextAlign.left,
      );
    });
  }

  void _alignSelectedTextCenter() {
    final element = selectedTextElement;

    if (element == null) return;

    setState(() {
      textElements = TextElementLogic.setAlignment(
        elements: textElements,
        elementId: element.id,
        alignment: TextAlign.center,
      );
    });
  }

  void _alignSelectedTextRight() {
    final element = selectedTextElement;

    if (element == null) return;

    setState(() {
      textElements = TextElementLogic.setAlignment(
        elements: textElements,
        elementId: element.id,
        alignment: TextAlign.right,
      );
    });
  }

  void _duplicateSelectedText() {
    final element = selectedTextElement;

    if (element == null) return;

    final duplicate = TextElementLogic.duplicateTextElement(
      element: element,
      newId: nextTextElementId,
      newZIndex: nextFrontZIndex,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );

    setState(() {
      textElements.add(duplicate);
      selectedTextElementId = duplicate.id;
      selectedShapeElementId = null;
      selectedImageElementId = null;

      nextTextElementId++;
      nextFrontZIndex++;
    });
  }

  void _duplicateSelectedShape() {
    final element = selectedShapeElement;

    if (element == null) return;

    final duplicate = ShapeElementLogic.duplicateShapeElement(
      element: element,
      newId: nextShapeElementId,
      newZIndex: nextFrontZIndex,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );

    setState(() {
      shapeElements.add(duplicate);
      selectedShapeElementId = duplicate.id;
      selectedTextElementId = null;
      selectedImageElementId = null;

      nextShapeElementId++;
      nextFrontZIndex++;
    });
  }

  void _duplicateSelectedImage() {
    final element = selectedImageElement;

    if (element == null) return;

    final duplicate = ImageElementLogic.duplicateImageElement(
      element: element,
      newId: nextImageElementId,
      newZIndex: nextFrontZIndex,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );

    setState(() {
      imageElements.add(duplicate);
      selectedImageElementId = duplicate.id;
      selectedTextElementId = null;
      selectedShapeElementId = null;

      nextImageElementId++;
      nextFrontZIndex++;
    });
  }

  void _deleteSelectedText() {
    final element = selectedTextElement;

    if (element == null) return;

    setState(() {
      textElements = TextElementLogic.deleteTextElement(
        elements: textElements,
        elementId: element.id,
      );

      selectedTextElementId = null;
    });
  }

  void _deleteSelectedShape() {
    final element = selectedShapeElement;

    if (element == null) return;

    setState(() {
      shapeElements = ShapeElementLogic.deleteShapeElement(
        elements: shapeElements,
        elementId: element.id,
      );

      selectedShapeElementId = null;
    });
  }

  void _deleteSelectedImage() {
    final element = selectedImageElement;

    if (element == null) return;

    setState(() {
      imageElements = ImageElementLogic.deleteImageElement(
        elements: imageElements,
        elementId: element.id,
      );

      selectedImageElementId = null;
    });
  }

  void _copySelectedElement() {
    final text = selectedTextElement;
    final shape = selectedShapeElement;
    final image = selectedImageElement;

    if (text != null) {
      copiedTextElement = ClipboardLogic.copyTextElement(text);
      copiedShapeElement = null;
      copiedImageElement = null;
      _showMessage('Text copied.');
      return;
    }

    if (shape != null) {
      copiedShapeElement = ClipboardLogic.copyShapeElement(shape);
      copiedTextElement = null;
      copiedImageElement = null;
      _showMessage('Shape copied.');
      return;
    }

    if (image != null) {
      copiedImageElement = ClipboardLogic.copyImageElement(image);
      copiedTextElement = null;
      copiedShapeElement = null;
      _showMessage('Image copied.');
      return;
    }
  }

  void _pasteCopiedElement() {
    if (copiedTextElement != null) {
      final pastedText = ClipboardLogic.pasteTextElement(
        copiedElement: copiedTextElement!,
        newId: nextTextElementId,
        newZIndex: nextFrontZIndex,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
      );

      setState(() {
        textElements.add(pastedText);
        selectedTextElementId = pastedText.id;
        selectedShapeElementId = null;
        selectedImageElementId = null;

        nextTextElementId++;
        nextFrontZIndex++;
      });

      _showMessage('Text pasted.');
      return;
    }

    if (copiedShapeElement != null) {
      final pastedShape = ClipboardLogic.pasteShapeElement(
        copiedElement: copiedShapeElement!,
        newId: nextShapeElementId,
        newZIndex: nextFrontZIndex,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
      );

      setState(() {
        shapeElements.add(pastedShape);
        selectedShapeElementId = pastedShape.id;
        selectedTextElementId = null;
        selectedImageElementId = null;

        nextShapeElementId++;
        nextFrontZIndex++;
      });

      _showMessage('Shape pasted.');
      return;
    }

    if (copiedImageElement != null) {
      final pastedImage = ClipboardLogic.pasteImageElement(
        copiedElement: copiedImageElement!,
        newId: nextImageElementId,
        newZIndex: nextFrontZIndex,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
      );

      setState(() {
        imageElements.add(pastedImage);
        selectedImageElementId = pastedImage.id;
        selectedTextElementId = null;
        selectedShapeElementId = null;

        nextImageElementId++;
        nextFrontZIndex++;
      });

      _showMessage('Image pasted.');
      return;
    }

    _showMessage('Nothing copied yet.');
  }

  void _bringSelectedElementToFront() {
    final text = selectedTextElement;
    final shape = selectedShapeElement;
    final image = selectedImageElement;

    setState(() {
      if (text != null) {
        textElements = ElementLayerLogic.bringTextToFront(
          elements: textElements,
          elementId: text.id,
          newZIndex: nextFrontZIndex,
        );

        nextFrontZIndex++;
      }

      if (shape != null) {
        shapeElements = ElementLayerLogic.bringShapeToFront(
          elements: shapeElements,
          elementId: shape.id,
          newZIndex: nextFrontZIndex,
        );

        nextFrontZIndex++;
      }

      if (image != null) {
        imageElements = ElementLayerLogic.bringImageToFront(
          elements: imageElements,
          elementId: image.id,
          newZIndex: nextFrontZIndex,
        );

        nextFrontZIndex++;
      }
    });

    _showMessage('Element brought to front.');
  }

  void _sendSelectedElementToBack() {
    final text = selectedTextElement;
    final shape = selectedShapeElement;
    final image = selectedImageElement;

    setState(() {
      if (text != null) {
        textElements = ElementLayerLogic.sendTextToBack(
          elements: textElements,
          elementId: text.id,
          newZIndex: nextBackZIndex,
        );

        nextBackZIndex--;
      }

      if (shape != null) {
        shapeElements = ElementLayerLogic.sendShapeToBack(
          elements: shapeElements,
          elementId: shape.id,
          newZIndex: nextBackZIndex,
        );

        nextBackZIndex--;
      }

      if (image != null) {
        imageElements = ElementLayerLogic.sendImageToBack(
          elements: imageElements,
          elementId: image.id,
          newZIndex: nextBackZIndex,
        );

        nextBackZIndex--;
      }
    });

    _showMessage('Element sent to back.');
  }

  Future<void> _showAlignmentMenu() async {
    final alignment = await showAlignmentDialog(context);

    if (alignment == null) return;

    _alignSelectedElement(alignment);
  }

  void _alignSelectedElement(String alignment) {
    final text = selectedTextElement;
    final shape = selectedShapeElement;
    final image = selectedImageElement;

    setState(() {
      if (text != null) {
        textElements = ElementLayerLogic.alignTextElement(
          elements: textElements,
          elementId: text.id,
          canvasWidth: canvasWidth,
          canvasHeight: canvasHeight,
          alignment: alignment,
        );
      }

      if (shape != null) {
        shapeElements = ElementLayerLogic.alignShapeElement(
          elements: shapeElements,
          elementId: shape.id,
          canvasWidth: canvasWidth,
          canvasHeight: canvasHeight,
          alignment: alignment,
        );
      }

      if (image != null) {
        imageElements = ElementLayerLogic.alignImageElement(
          elements: imageElements,
          elementId: image.id,
          canvasWidth: canvasWidth,
          canvasHeight: canvasHeight,
          alignment: alignment,
        );
      }
    });
  }

  Future<void> _showElementOptionsMenu() async {
    final action = await showElementOptionsDialog(context);

    if (action == null) return;

    switch (action) {
      case ElementOptionAction.copy:
        _copySelectedElement();
        break;

      case ElementOptionAction.paste:
        _pasteCopiedElement();
        break;

      case ElementOptionAction.duplicate:
        if (selectedTextElement != null) {
          _duplicateSelectedText();
        } else if (selectedShapeElement != null) {
          _duplicateSelectedShape();
        } else {
          _duplicateSelectedImage();
        }
        break;

      case ElementOptionAction.delete:
        if (selectedTextElement != null) {
          _deleteSelectedText();
        } else if (selectedShapeElement != null) {
          _deleteSelectedShape();
        } else {
          _deleteSelectedImage();
        }
        break;

      case ElementOptionAction.bringToFront:
        _bringSelectedElementToFront();
        break;

      case ElementOptionAction.sendToBack:
        _sendSelectedElementToBack();
        break;

      case ElementOptionAction.alignment:
        _showAlignmentMenu();
        break;
    }
  }

  void _handleToolTap(int index) {
    setState(() {
      selectedToolIndex = index;
    });

    if (index == 0) {
      _addTextElement();
      return;
    }

    if (index == 1) {
      _showShapePicker();
      return;
    }

    if (index == 2) {
      _pickImageFromCameraRoll();
      return;
    }

    if (index == 3) {
      _openUploadsPanel();
      return;
    }

    if (index == 4) {
      _openPortfoliosPanel();
    }
  }

  void _showEditorMenu() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _menuItem(
                  icon: Icons.save_outlined,
                  label: 'Save Portfolio',
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _savePortfolio();
                  },
                ),
                _menuItem(
                  icon: Icons.delete_outline,
                  label: 'Delete Portfolio',
                  isDanger: true,
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _showMessage('Delete portfolio prototype only.');
                  },
                ),
                _menuItem(
                  icon: Icons.help_outline,
                  label: 'Help',
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _showMessage('Help guide will be added next.');
                  },
                ),
                _menuItem(
                  icon: Icons.report_outlined,
                  label: 'Report',
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _showMessage('Report option prototype only.');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDanger ? AppColors.danger : AppColors.white,
              size: 21,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isDanger ? AppColors.danger : AppColors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeText = selectedTextElement;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            EditorTopBar(
              onBack: () {
                Navigator.pop(context);
              },
              onUndo: () {
                _showMessage('Undo action prototype.');
              },
              onRedo: () {
                _showMessage('Redo action prototype.');
              },
              onMenu: _showEditorMenu,
              title: portfolioTitle,
            ),

            EditorCanvas(
              canvasLabel: canvasLabel,
              canvasMeasurement: canvasMeasurement,
              canvasWidth: canvasWidth,
              canvasHeight: canvasHeight,
              textElements: textElements,
              shapeElements: shapeElements,
              imageElements: imageElements,
              selectedTextElementId: selectedTextElementId,
              selectedShapeElementId: selectedShapeElementId,
              selectedImageElementId: selectedImageElementId,
              onCanvasTap: _unselectElements,
              onSelectTextElement: _selectTextElement,
              onMoveTextElement: _moveTextElement,
              onResizeTextElement: _resizeTextElement,
              onSelectShapeElement: _selectShapeElement,
              onMoveShapeElement: _moveShapeElement,
              onResizeShapeElement: _resizeShapeElement,
              onSelectImageElement: _selectImageElement,
              onMoveImageElement: _moveImageElement,
              onResizeImageElement: _resizeImageElement,
            ),

            TextElementActions(
              isVisible: activeText != null,
              fontSize: activeText?.fontSize ?? 14,
              isBold: activeText?.isBold ?? false,
              isItalic: activeText?.isItalic ?? false,
              isUnderline: activeText?.isUnderline ?? false,
              fontFamily: activeText?.fontFamily ?? 'sans-serif',
              textAlign: activeText?.textAlign ?? TextAlign.center,
              onEdit: _editSelectedText,
              onDuplicate: _duplicateSelectedText,
              onDelete: _deleteSelectedText,
              onMore: _showElementOptionsMenu,
              onDecreaseFont: _decreaseSelectedFontSize,
              onIncreaseFont: _increaseSelectedFontSize,
              onToggleBold: _toggleSelectedBold,
              onToggleItalic: _toggleSelectedItalic,
              onToggleUnderline: _toggleSelectedUnderline,
              onPickFontStyle: _pickSelectedFontStyle,
              onAlignLeft: _alignSelectedTextLeft,
              onAlignCenter: _alignSelectedTextCenter,
              onAlignRight: _alignSelectedTextRight,
              onPickColor: _pickSelectedTextColor,
            ),

            ShapeElementActions(
              isVisible: selectedShapeElement != null,
              onDuplicate: _duplicateSelectedShape,
              onDelete: _deleteSelectedShape,
              onPickColor: _pickSelectedShapeColor,
              onMore: _showElementOptionsMenu,
            ),

            ImageElementActions(
              isVisible: selectedImageElement != null,
              onDuplicate: _duplicateSelectedImage,
              onDelete: _deleteSelectedImage,
              onMore: _showElementOptionsMenu,
            ),

            EditorPageSection(
              selectedPageIndex: selectedPageIndex,
              pageCount: pages.length,
              onSelectPage: _selectPage,
              onAddPage: _addNewPage,
              onAddSection: _addNewPage,
            ),

            EditorBottomToolbar(
              selectedToolIndex: selectedToolIndex,
              onToolTap: _handleToolTap,
            ),
          ],
        ),
      ),
    );
  }
}