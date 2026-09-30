# قراءة المجال المغناطيسي (Magnetometer) في iOS

هذا المشروع تطبيق SwiftUI بسيط يقرأ حسّاس المجال المغناطيسي في الآيفون باستخدام إطار **Core Motion**. يعرض التطبيق:

- مكوّنات المجال على المحاور الثلاثة **x وy وz** بوحدة الميكروتسلا (µT).
- **القيمة المطلقة** للمجال (مقداره الكلي).
- وضعين للقراءة: **معايَر (Calibrated)** و**خام (Raw)**.
- دقة المعايرة، ورسم بياني لآخر 5 ثوانٍ، و"كاشف معادن" بسيط.

كل منطق الحسّاس موجود في ملف واحد، هو `MagnetometerManager.swift`. يمكن نسخ هذا الملف إلى أي تطبيق آخر واستخدامه مباشرة.

---

## المتطلبات

- Xcode 16 أو أحدث.
- iOS 17 أو أحدث.
- **جهاز آيفون حقيقي**، لأن المحاكي (Simulator) لا يحتوي على حسّاس مغناطيسي.
- لا يحتاج التطبيق إلى أي إذن من المستخدم، ولا إلى أي مفتاح في `Info.plist`.

## التشغيل

1. افتح الملف `MagnetometerDemo.xcodeproj`.
2. من الهدف **MagnetometerDemo** اختر *Signing & Capabilities*، ثم اختر فريق التطوير (Team).
3. شغّل التطبيق على الآيفون.

---

## هيكل الملفات

| الملف | وظيفته |
| --- | --- |
| `MagnetometerManager.swift` | كل كود Core Motion: طريقتا القراءة، وحساب القيمة المطلقة، والتشغيل والإيقاف، وخط الأساس |
| `ContentView.swift` | الواجهة: عرض القيم، وأشرطة المحاور، والرسم البياني، وكاشف المعادن |
| `MagnetometerDemoApp.swift` | نقطة بداية التطبيق |

---

## شرح الكود

### 1. المحاور الثلاثة x وy وz

القيم تُقاس بالنسبة لمحاور **الجهاز نفسه**:

- **x**: باتجاه الحافة اليمنى للشاشة.
- **y**: باتجاه أعلى الشاشة.
- **z**: خارج من الشاشة باتجاه المستخدم.

لذلك تتغير قيم x وy وz عند تدوير الجوال، لأن المحاور تدور معه.

### 2. القيمة المطلقة (المقدار)

القيمة المطلقة هي طول المتّجه (x, y, z):

```
|B| = √(x² + y² + z²)
```

وفي الكود:

```swift
var magnitude: Double {
    (x * x + y * y + z * z).squareRoot()
}
```

**لماذا هي مهمة؟** لأنها **لا تتغير عند تدوير الجوال**، فتدوير المتّجه لا يغيّر طوله. لهذا هي القيمة المناسبة لاكتشاف المغناطيس والمعادن الحديدية.

القيمة الطبيعية للمجال المغناطيسي للأرض بين 25 و65 µT تقريبًا حسب الموقع، وهي نحو **40 µT** في السعودية.

### 3. طريقتا القراءة

#### الطريقة الأولى: القراءة المعايَرة (الموصى بها)

تأتي من `CMDeviceMotion.magneticField`. في هذه الطريقة يزيل النظام التشويش المغناطيسي الناتج عن مكوّنات الجوال نفسه (hard-iron bias).

```swift
motionManager.deviceMotionUpdateInterval = 1.0 / 30.0

motionManager.startDeviceMotionUpdates(
    using: .xArbitraryCorrectedZVertical,   // مهم جدًا
    to: .main
) { motion, error in
    guard let motion else { return }
    let field = motion.magneticField
    let x = field.field.x
    let y = field.field.y
    let z = field.field.z
    let accuracy = field.accuracy          // دقة المعايرة
}
```

⚠️ **ملاحظة مهمة:** يجب استخدام الإطار المرجعي `.xArbitraryCorrectedZVertical` أو `.xMagneticNorthZVertical`. الإطار الافتراضي لا يستخدم الحسّاس المغناطيسي، فتبقى القيم صفرًا.

**دقة المعايرة (`accuracy`):** تبدأ بقيمة `.uncalibrated`، ثم تتحسن إلى `.low` ثم `.medium` ثم `.high` كلما تحرك الجوال. تحريك الجوال على شكل الرقم 8 يسرّع المعايرة. ويعرض النظام تلقائيًا رسالة تطلب ذلك من المستخدم عند الحاجة بفضل هذا السطر:

```swift
motionManager.showsDeviceMovementDisplay = true
```

#### الطريقة الثانية: القراءة الخام

تأتي مباشرة من الحسّاس عبر `CMMagnetometerData`، وتشمل تشويش الجوال نفسه. لذلك قد تصل القيمة المطلقة إلى مئات الميكروتسلا حتى بعيدًا عن أي مغناطيس، ولا تتوفر معها معلومة الدقة.

```swift
motionManager.magnetometerUpdateInterval = 1.0 / 30.0

motionManager.startMagnetometerUpdates(to: .main) { data, error in
    guard let data else { return }
    let x = data.magneticField.x
    let y = data.magneticField.y
    let z = data.magneticField.z
}
```

**متى تُستخدم؟** نادرًا، مثلًا عند الحاجة إلى البيانات الأصلية لتطبيق خوارزمية معايرة خاصة.

### 4. التشغيل والإيقاف

```swift
.onAppear    { magnetometer.start() }
.onDisappear { magnetometer.stop() }
```

- يجب **إيقاف** التحديثات عند عدم الحاجة إليها، لأن الحسّاس يستهلك البطارية طوال فترة عمله.
- يُفضَّل استخدام **نسخة واحدة فقط** من `CMMotionManager` في التطبيق كله (توصية Apple).
- تردد 30 مرة في الثانية كافٍ للواجهة ومناسب للبطارية.
- إذا كانت معالجة كل قراءة ثقيلة، فمرّر `OperationQueue` خاصًا بدل `.main`، ثم حدّث الواجهة على الخيط الرئيسي.

### 5. كاشف المعادن (خط الأساس)

الفكرة بسيطة:

1. يحفظ المستخدم قيمة المجال الحالية، بعيدًا عن المعادن، كـ"خط أساس" (baseline).
2. يحسب التطبيق باستمرار الفرق بين القيمة الحالية وخط الأساس.
3. إذا تجاوز الفرق 10 µT، يعرض التطبيق تنبيهًا بوجود جسم مغناطيسي أو معدني قريب.

```swift
func captureBaseline() { baseline = magnitude }

var deltaFromBaseline: Double? {
    baseline.map { magnitude - $0 }
}
```

### 6. التحقق من توفّر الحسّاس

```swift
motionManager.isDeviceMotionAvailable   // للقراءة المعايَرة
motionManager.isMagnetometerAvailable   // للقراءة الخام
```

تكون القيمة `false` في المحاكي، وعندها تعرض الواجهة رسالة "No Magnetometer".

---

## الاستخدام في تطبيقك

1. انسخ الملف `MagnetometerManager.swift` إلى مشروعك.
2. استخدمه في أي View:

```swift
import SwiftUI

struct MyView: View {
    @State private var magnetometer = MagnetometerManager()

    var body: some View {
        VStack {
            Text("X: \(magnetometer.x, specifier: "%.1f") µT")
            Text("Y: \(magnetometer.y, specifier: "%.1f") µT")
            Text("Z: \(magnetometer.z, specifier: "%.1f") µT")
            Text("|B|: \(magnetometer.magnitude, specifier: "%.1f") µT")
                .bold()
        }
        .onAppear { magnetometer.start() }
        .onDisappear { magnetometer.stop() }
    }
}
```

3. للتبديل إلى القراءة الخام:

```swift
magnetometer.mode = .raw
```

### الخصائص المتاحة في `MagnetometerManager`

| الخاصية / الدالة | الوصف |
| --- | --- |
| `x`, `y`, `z` | مكوّنات المجال بالميكروتسلا |
| `magnitude` | القيمة المطلقة √(x² + y² + z²) |
| `mode` | `.calibrated` (افتراضي) أو `.raw` |
| `accuracy` / `accuracyDescription` | دقة المعايرة (في الوضع المعايَر فقط) |
| `history` | آخر 150 قراءة للقيمة المطلقة (للرسم البياني) |
| `isAvailable` | هل الحسّاس متوفر على الجهاز؟ |
| `isRunning` | هل التحديثات تعمل حاليًا؟ |
| `start()` / `stop()` | تشغيل وإيقاف القراءات |
| `captureBaseline()` / `clearBaseline()` | حفظ خط الأساس وحذفه |
| `deltaFromBaseline` | الفرق عن خط الأساس |

---

## تجارب مقترحة

- **دوّر الجوال:** ستتغير قيم x وy وz، بينما تبقى القيمة المطلقة شبه ثابتة (نحو 40 µT في الرياض في الوضع المعايَر).
- **بدّل إلى الوضع الخام:** سترتفع القيمة المطلقة بسبب تشويش الجوال نفسه.
- **جرّب كاشف المعادن:** احفظ خط الأساس، ثم قرّب الجوال من مغناطيس أو ملعقة حديد أو مفصل لابتوب.
