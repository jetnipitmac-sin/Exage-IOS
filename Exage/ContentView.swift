import SwiftUI
import Combine
import Charts
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Models
struct ActivityTag: Identifiable, Hashable {
    let id: String
    let labelTh: String
    let labelEn: String
    let color: Color
}

struct StudyPlan: Identifiable, Codable {
    var id = UUID()
    var title: String
    var subject: String
    var date: Date
    var deadline: Date?
    var targetHours: Double = 1.0
    var trackedSeconds: Int = 0
    var activityTag: String = "theory"
    var isCompleted: Bool = false
    var notificationId: String?
}

enum ChartStyle: String, CaseIterable, Identifiable {
    case bar, line, point, pie
    var id: Self { self }
}

struct DailyStat: Identifiable, Codable {
    var id = UUID()
    let day: String
    var hours: Double
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let isFile: Bool
}

struct AIJsonResponse: Codable {
    let replyText: String
    let exams: [ExamItem]?
    let newPlans: [NewPlanItem]?
}

struct ExamItem: Codable {
    let subject: String
    let daysUntilExam: Int
}

struct NewPlanItem: Codable {
    let title: String
    let subject: String
    let dayOffset: Int
    let deadlineOffset: Int?
    let targetHours: Double?
    let activityTag: String?
}

enum DayOfWeek: String, CaseIterable, Codable, Identifiable {
    case monday = "Mon", tuesday = "Tue", wednesday = "Wed", thursday = "Thu", friday = "Fri", saturday = "Sat", sunday = "Sun"
    var id: Self { self }
}

struct TimeRange: Codable, Hashable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
}

enum ThemeMode: String, CaseIterable, Codable, Identifiable {
    case light = "Light", dark = "Dark", coolBlue = "Cool Blue"
    var id: Self { self }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case thai = "🇹🇭 ไทย", english = "🇬🇧 English"
    var id: Self { self }
}

let MOCK_TAGS = [
    ActivityTag(id: "theory", labelTh: "อ่านทฤษฎี", labelEn: "Theory", color: .blue),
    ActivityTag(id: "practice", labelTh: "ทำแบบฝึกหัด", labelEn: "Practice", color: .green),
    ActivityTag(id: "review", labelTh: "ทบทวน", labelEn: "Review", color: .orange)
]

let DEFAULT_STATS: [DailyStat] = [
    DailyStat(day: "Mon", hours: 0.0), DailyStat(day: "Tue", hours: 0.0), DailyStat(day: "Wed", hours: 0.0),
    DailyStat(day: "Thu", hours: 0.0), DailyStat(day: "Fri", hours: 0.0), DailyStat(day: "Sat", hours: 0.0), DailyStat(day: "Sun", hours: 0.0)
]

// MARK: - ViewModel
class AppViewModel: ObservableObject {
    @Published var activeTab: Int = 0
    @Published var isTracking: Bool = false
    @Published var seconds: Int = 0
    @Published var selectedTags: Set<String> = []
    @Published var selectedChartStyle: ChartStyle = .bar
    @Published var selectedPlanId: UUID? = nil
    
    // ตั้งค่าแอป
    @Published var themeMode: ThemeMode = .light { didSet { saveToStorage(data: themeMode, key: "saved_theme") } }
    @Published var language: AppLanguage = .thai { didSet { saveToStorage(data: language, key: "saved_language") } }
    
    // ข้อมูล
    @Published var fatigueLevel: Double = 0.0 { didSet { UserDefaults.standard.set(fatigueLevel, forKey: "saved_fatigue") } }
    @Published var subjects: [String] = [] { didSet { saveToStorage(data: subjects, key: "saved_subjects") } }
    @Published var selectedSubject: String = ""
    @Published var subjectExams: [String: Date] = [:] { didSet { saveToStorage(data: subjectExams, key: "saved_subject_exams") } }
    @Published var studyPlans: [StudyPlan] = [] { didSet { saveToStorage(data: studyPlans, key: "saved_plans") } }
    @Published var weeklyStats: [DailyStat] = [] { didSet { saveToStorage(data: weeklyStats, key: "saved_stats") } }
    @Published var freeTimeSettings: [DayOfWeek: [TimeRange]] = [:] { didSet { saveToStorage(data: freeTimeSettings, key: "saved_free_time") } }
    
    @Published var chatMessages: [ChatMessage] = []
    @Published var isAITyping: Bool = false
    
    var timer: Timer?
    
    // 🎨 Theme Colors
    var themeBg: Color {
        if themeMode == .coolBlue { return Color(red: 0.05, green: 0.1, blue: 0.18) }
        return Color(UIColor.systemGroupedBackground)
    }
    var themeCardBg: Color {
        if themeMode == .coolBlue { return Color(red: 0.1, green: 0.15, blue: 0.25) }
        return Color(UIColor.secondarySystemGroupedBackground)
    }
    var themeAccent: Color {
        switch themeMode { case .light: return .indigo; case .dark: return .yellow; case .coolBlue: return .cyan }
    }
    
    // 🌐 Translation Helper
    func t(_ th: String, _ en: String) -> String { return language == .thai ? th : en }
    
    init() {
        loadAllData()
        requestNotificationPermission()
        if chatMessages.isEmpty {
            chatMessages = [ChatMessage(text: t("สวัสดีครับ! 🧪\nผม BrainFlow พร้อมช่วยวิเคราะห์ จัดตาราง และแยกย่อยเนื้อหาให้คุณแล้วครับ พิมพ์สั่งได้เลย!", "Hello! 🧪\nI'm BrainFlow. I can help you analyze, schedule, and breakdown study tasks. Just ask!"), isUser: false, isFile: false)]
        }
    }
    
    private func saveToStorage<T: Encodable>(data: T, key: String) {
        if let encoded = try? JSONEncoder().encode(data) { UserDefaults.standard.set(encoded, forKey: key) }
    }
    
    private func loadAllData() {
        if let data = UserDefaults.standard.data(forKey: "saved_theme"), let decoded = try? JSONDecoder().decode(ThemeMode.self, from: data) { self.themeMode = decoded }
        if let data = UserDefaults.standard.data(forKey: "saved_language"), let decoded = try? JSONDecoder().decode(AppLanguage.self, from: data) { self.language = decoded }
        
        self.fatigueLevel = UserDefaults.standard.double(forKey: "saved_fatigue")
        if let data = UserDefaults.standard.data(forKey: "saved_subjects"), let decoded = try? JSONDecoder().decode([String].self, from: data) { self.subjects = decoded }
        else { self.subjects = ["Calculus", "Physics 2", "Chemistry", "English"] }
        self.selectedSubject = self.subjects.first ?? "Calculus"
        
        if let data = UserDefaults.standard.data(forKey: "saved_subject_exams"), let decoded = try? JSONDecoder().decode([String: Date].self, from: data) { self.subjectExams = decoded }
        if let data = UserDefaults.standard.data(forKey: "saved_plans"), let decoded = try? JSONDecoder().decode([StudyPlan].self, from: data) { self.studyPlans = decoded }
        if let data = UserDefaults.standard.data(forKey: "saved_stats"), let decoded = try? JSONDecoder().decode([DailyStat].self, from: data) { self.weeklyStats = decoded } else { self.weeklyStats = DEFAULT_STATS }
        if let data = UserDefaults.standard.data(forKey: "saved_free_time"), let decoded = try? JSONDecoder().decode([DayOfWeek: [TimeRange]].self, from: data) { self.freeTimeSettings = decoded } else {
            for day in DayOfWeek.allCases { self.freeTimeSettings[day] = [] }
        }
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in }
    }
    
    func scheduleNotification(for plan: StudyPlan) {
        let content = UNMutableNotificationContent()
        content.title = t("ได้เวลาอัปเกรดสมองแล้ว!", "Time to upgrade your brain!")
        content.body = t("เตรียมตัวอ่านวิชา \(plan.subject) เรื่อง \(plan.title) ในอีก 15 นาที", "Get ready to study \(plan.subject) : \(plan.title) in 15 mins.")
        content.sound = .default
        
        let triggerDate = plan.date.addingTimeInterval(-15 * 60)
        if triggerDate > Date() {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: plan.notificationId ?? UUID().uuidString, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    func cancelNotification(identifier: String?) {
        if let id = identifier { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id]) }
    }
    
    // MARK: - Timer
    func toggleTracking() {
        if isTracking { stopTimer() } else { startTimer() }
        isTracking.toggle()
    }
    
    private func startTimer() {
        let fatiguePerSecond = 20.0 / 3600.0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.seconds += 1
            self.fatigueLevel = min(100.0, self.fatigueLevel + fatiguePerSecond)
            
            if let planId = self.selectedPlanId, let index = self.studyPlans.firstIndex(where: { $0.id == planId }) {
                self.studyPlans[index].trackedSeconds += 1
                let targetSecs = Int(self.studyPlans[index].targetHours * 3600)
                if self.studyPlans[index].trackedSeconds >= targetSecs && !self.studyPlans[index].isCompleted {
                    self.studyPlans[index].isCompleted = true
                }
            }
        }
    }
    
    func stopTimer() { timer?.invalidate(); timer = nil }
    
    func saveSession() {
        stopTimer()
        if let lastIndex = weeklyStats.indices.last { weeklyStats[lastIndex].hours += Double(seconds) / 3600.0 }
        isTracking = false; seconds = 0; selectedTags.removeAll(); selectedPlanId = nil
    }
    
    func applyRest(recoveryPercentage: Double) { self.fatigueLevel = max(0.0, self.fatigueLevel - recoveryPercentage) }
    
    func addNewSubject(_ newSubject: String) {
        let trimmed = newSubject.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !subjects.contains(trimmed) { subjects.append(trimmed); selectedSubject = trimmed }
    }
    
    func addNewPlan(title: String, subject: String, date: Date, deadline: Date? = nil, targetHours: Double = 1.0, activityTag: String = "theory") {
        let notifId = UUID().uuidString
        let newPlan = StudyPlan(id: UUID(), title: title, subject: subject, date: date, deadline: deadline, targetHours: targetHours, trackedSeconds: 0, activityTag: activityTag, isCompleted: false, notificationId: notifId)
        studyPlans.append(newPlan); studyPlans.sort { $0.date < $1.date }
        scheduleNotification(for: newPlan)
    }
    
    func deletePlan(plan: StudyPlan) {
        cancelNotification(identifier: plan.notificationId)
        studyPlans.removeAll { $0.id == plan.id }
    }
    
    func deleteAllDeadlines(for subject: String) {
        for i in 0..<studyPlans.count { if studyPlans[i].subject == subject { studyPlans[i].deadline = nil } }
        objectWillChange.send()
    }
    
    func emergencyRescheduleWithAI() {
        let pendingPlans = studyPlans.filter { !$0.isCompleted }
        if pendingPlans.isEmpty { return }
        let plansText = pendingPlans.map { "- \($0.title) (\($0.subject))" }.joined(separator: "\n")
        let message = t("ด่วน! มีงานค้างอยู่:\n\(plansText)\nช่วยจัดตารางให้ใหม่เริ่มตั้งแต่พรุ่งนี้ เกลี่ยให้ทัน Deadline นะ", "Urgent! I have pending tasks:\n\(plansText)\nPlease reschedule them starting tomorrow, balancing before deadlines.")
        self.activeTab = 4
        self.askAI(message: message, isEmergency: true)
    }
    
    func clearAIChat() {
        chatMessages = [ChatMessage(text: t("รีเซ็ตความจำเรียบร้อยครับ! มีอะไรให้จัดตารางหรือวิเคราะห์ไฟล์ บอกได้เลย 🧹✨", "Memory cleared! What would you like to schedule or analyze today? 🧹✨"), isUser: false, isFile: false)]
    }
    
    func timeString(time: Int) -> String { return String(format: "%02i:%02i:%02i", time / 3600, (time % 3600) / 60, time % 60) }
    
    func getFormattedFreeTimeSettings() -> String {
        var report = t("เวลาว่างของผู้ใช้ (ใช้อ้างอิงจัดตาราง):\n", "User's free time (for scheduling reference):\n")
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        for day in DayOfWeek.allCases {
            report += "- \(day.rawValue): "
            if let ranges = freeTimeSettings[day], !ranges.isEmpty {
                report += ranges.map { "\(formatter.string(from: $0.start))-\(formatter.string(from: $0.end))" }.joined(separator: ", ")
            } else { report += t("ไม่ว่าง", "Busy") }
            report += "\n"
        }
        return report
    }
    
    // MARK: - AI
    func askAI(message: String, isEmergency: Bool = false, isFile: Bool = false) {
        chatMessages.append(ChatMessage(text: message, isUser: true, isFile: isFile))
        isAITyping = true
        
        // 🚨 นำ API KEY ของคุณมาใส่ที่นี่ 🚨
        let apiKey = "YOUR_API_KEY_HERE"
        
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(cleanKey)"
        guard let url = URL(string: urlString) else { return }
        
        let contextMessage = isFile ? t("ผู้ใช้อัปโหลดไฟล์: '\(message)' ช่วยวิเคราะห์แตกเนื้อหาย่อยและจัดตาราง", "User uploaded file: '\(message)'. Analyze and schedule tasks based on it.") : t("ผู้ใช้ถาม: \"\(message)\"", "User says: \"\(message)\"")
        let freeTimeInfo = getFormattedFreeTimeSettings()
        let languageInstruction = language == .thai ? "ตอบกลับเป็นภาษาไทย (Thai) เท่านั้น" : "Reply in English only."
        
        let systemPrompt = """
        คุณคือ AI ผู้ช่วยวางแผนการเรียนชื่อ BrainFlow
        \(contextMessage)
        
        \(freeTimeInfo)
        
        \(languageInstruction)
        ตอบกลับด้วย JSON Format เท่านั้น ห้ามมีข้อความอื่น:
        {
          "replyText": "คำตอบพูดคุย (ห้ามขึ้นบรรทัดใหม่)",
          "exams": [ { "subject": "วิชา", "daysUntilExam": 14 } ],
          "newPlans": [
            { "title": "ชื่อเรื่องย่อย", "subject": "วิชา", "dayOffset": 1, "deadlineOffset": 5, "targetHours": 1.5, "activityTag": "theory" }
          ]
        }
        activityTag เลือกจาก: theory, practice, review
        ถ้าไม่ตั้งค่าไหนให้ใส่ null
        """
        
        let requestBody: [String: Any] = [
            "contents": [ ["parts": [["text": systemPrompt]]] ],
            "generationConfig": [ "responseMimeType": "application/json" ]
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isAITyping = false
                guard let data = data, error == nil else {
                    self.chatMessages.append(ChatMessage(text: self.t("ขออภัยครับ ไม่สามารถเชื่อมต่อเน็ตได้ 📡", "Sorry, internet connection failed. 📡"), isUser: false, isFile: false))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    self.chatMessages.append(ChatMessage(text: self.t("⚠️ เกิดข้อผิดพลาดกับเซิร์ฟเวอร์ (Code: \(httpResponse.statusCode))", "⚠️ Server Error (Code: \(httpResponse.statusCode))"), isUser: false, isFile: false))
                    return
                }
                self.processRealAIResponse(data: data, isEmergency: isEmergency)
            }
        }.resume()
    }
    
    private func processRealAIResponse(data: Data, isEmergency: Bool) {
        do {
            struct GeminiResponse: Decodable {
                struct Candidate: Decodable { struct Content: Decodable { struct Part: Decodable { let text: String }; let parts: [Part] }; let content: Content }
                let candidates: [Candidate]
            }
            
            let result = try JSONDecoder().decode(GeminiResponse.self, from: data)
            guard let rawText = result.candidates.first?.content.parts.first?.text else { return }
            
            var cleanJSON = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanJSON.hasPrefix("```json") { cleanJSON = String(cleanJSON.dropFirst(7)) }
            else if cleanJSON.hasPrefix("```") { cleanJSON = String(cleanJSON.dropFirst(3)) }
            if cleanJSON.hasSuffix("```") { cleanJSON = String(cleanJSON.dropLast(3)) }
            cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let jsonData = cleanJSON.data(using: .utf8) else { return }
            let aiData = try JSONDecoder().decode(AIJsonResponse.self, from: jsonData)
            
            chatMessages.append(ChatMessage(text: aiData.replyText, isUser: false, isFile: false))
            
            if let exams = aiData.exams {
                for exam in exams {
                    let examDate = Calendar.current.date(byAdding: .day, value: exam.daysUntilExam, to: Date()) ?? Date()
                    if !self.subjects.contains(exam.subject) { self.addNewSubject(exam.subject) }
                    self.subjectExams[exam.subject] = examDate
                }
            }
            
            if let plans = aiData.newPlans, !plans.isEmpty {
                if isEmergency {
                    let pending = self.studyPlans.filter { !$0.isCompleted }
                    for p in pending { self.cancelNotification(identifier: p.notificationId) }
                    self.studyPlans.removeAll { !$0.isCompleted }
                }
                for plan in plans {
                    let targetDate = Calendar.current.date(byAdding: .day, value: plan.dayOffset, to: Date()) ?? Date()
                    var deadlineDate: Date? = nil
                    if let dOffset = plan.deadlineOffset { deadlineDate = Calendar.current.date(byAdding: .day, value: dOffset, to: Date()) }
                    if !self.subjects.contains(plan.subject) { self.addNewSubject(plan.subject) }
                    let safeTag = plan.activityTag ?? "theory"
                    let safeHours = plan.targetHours ?? 1.0
                    self.addNewPlan(title: plan.title, subject: plan.subject, date: targetDate, deadline: deadlineDate, targetHours: safeHours, activityTag: safeTag)
                }
            }
        } catch {
            self.chatMessages.append(ChatMessage(text: self.t("ประมวลผลข้อความผิดพลาด กรุณาลองใหม่อีกครั้งครับ 😅", "Error parsing response. Please try again 😅"), isUser: false, isFile: false))
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject var viewModel = AppViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            HeaderView(viewModel: viewModel)
            
            TabView(selection: $viewModel.activeTab) {
                TrackerView(viewModel: viewModel).tabItem { Image(systemName: "clock.fill"); Text(viewModel.t("จับเวลา", "Timer")) }.tag(0)
                CalendarView(viewModel: viewModel).tabItem { Image(systemName: "square.grid.2x2.fill"); Text(viewModel.t("แผน", "Plan")) }.tag(1)
                AnalyticsView(viewModel: viewModel).tabItem { Image(systemName: "chart.bar.fill"); Text(viewModel.t("สถิติ", "Stats")) }.tag(2)
                BurnoutView(viewModel: viewModel).tabItem { Image(systemName: "leaf.fill"); Text(viewModel.t("พักสมอง", "Rest")) }.tag(3)
                AIAssistantView(viewModel: viewModel).tabItem { Image(systemName: "sparkles"); Text(viewModel.t("ผู้ช่วย AI", "AI")) }.tag(4)
            }
            .accentColor(viewModel.themeAccent)
        }
        .preferredColorScheme(viewModel.themeMode == .light ? .light : .dark)
    }
}

struct HeaderView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showSettings = false
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile").font(.title).foregroundColor(viewModel.themeAccent)
                Text("BrainFlow").font(.title2).fontWeight(.bold).foregroundColor(viewModel.themeAccent)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(viewModel.t("ความล้า", "Fatigue")).font(.caption).foregroundColor(.gray)
                Text("\(Int(viewModel.fatigueLevel))%").font(.headline).foregroundColor(viewModel.fatigueLevel > 80 ? .red : (viewModel.fatigueLevel > 50 ? .orange : .green))
            }
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill").font(.title2).foregroundColor(.gray).padding(.leading, 10)
            }
        }
        .padding().background(viewModel.themeCardBg)
        .sheet(isPresented: $showSettings) { GlobalSettingsView(viewModel: viewModel) }
    }
}

struct GlobalSettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedDay: DayOfWeek = .monday
    @State private var startTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date().addingTimeInterval(3600)
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(viewModel.t("ภาษา (Language)", "Language"))) {
                    Picker("Language", selection: $viewModel.language) {
                        ForEach(AppLanguage.allCases) { lang in Text(lang.rawValue).tag(lang) }
                    }.pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text(viewModel.t("ลักษณะแอป (Theme)", "App Theme"))) {
                    Picker("Theme", selection: $viewModel.themeMode) {
                        ForEach(ThemeMode.allCases) { theme in Text(theme.rawValue).tag(theme) }
                    }.pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text(viewModel.t("เพิ่มช่วงเวลาว่าง (ให้ AI จัดตาราง)", "Add Free Time (For AI Scheduling)"))) {
                    Picker(viewModel.t("วัน", "Day"), selection: $selectedDay) { ForEach(DayOfWeek.allCases) { day in Text(day.rawValue).tag(day) } }
                    DatePicker(viewModel.t("เริ่ม", "Start"), selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker(viewModel.t("สิ้นสุด", "End"), selection: $endTime, displayedComponents: .hourAndMinute)
                    Button(viewModel.t("เพิ่มช่วงเวลา", "Add Time Slot")) {
                        let newRange = TimeRange(start: startTime, end: endTime)
                        viewModel.freeTimeSettings[selectedDay, default: []].append(newRange)
                    }.disabled(startTime >= endTime)
                }
                
                ForEach(DayOfWeek.allCases) { day in
                    Section(header: Text(day.rawValue)) {
                        let ranges = viewModel.freeTimeSettings[day] ?? []
                        if ranges.isEmpty { Text(viewModel.t("ไม่มีเวลาว่างที่บันทึกไว้", "No free time saved")).foregroundColor(.gray).font(.caption) } else {
                            ForEach(ranges) { range in
                                HStack {
                                    Image(systemName: "clock").foregroundColor(viewModel.themeAccent)
                                    Text("\(range.start.formatted(date: .omitted, time: .shortened)) - \(range.end.formatted(date: .omitted, time: .shortened))")
                                    Spacer()
                                }
                            }.onDelete { indexSet in viewModel.freeTimeSettings[day]?.remove(atOffsets: indexSet) }
                        }
                    }
                }
            }
            .navigationTitle(viewModel.t("ตั้งค่าแอป", "Settings"))
            .navigationBarItems(trailing: Button(viewModel.t("ปิด", "Close")) { presentationMode.wrappedValue.dismiss() })
        }
        .preferredColorScheme(viewModel.themeMode == .light ? .light : .dark)
    }
}

// MARK: - 1. Tracker View
struct TrackerView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var newSubjectText: String = ""
    @State private var showAddSubject: Bool = false
    
    var body: some View {
        ZStack {
            viewModel.themeBg.edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 30) {
                    if viewModel.fatigueLevel > 80 {
                        HStack { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red); VStack(alignment: .leading) { Text(viewModel.t("สมองคุณล้ามากแล้ว!", "Your brain is exhausted!")).font(.headline).foregroundColor(.red); Text(viewModel.t("แวะไปหน้า 'พักสมอง' เพื่อชาร์จพลังก่อนดีกว่า", "Go to the Rest tab to recharge.")).font(.subheadline).foregroundColor(.red.opacity(0.8)) }; Spacer() }.padding().background(Color.red.opacity(0.1)).cornerRadius(12).padding(.horizontal)
                    }
                    
                    ZStack { Circle().stroke(viewModel.isTracking ? viewModel.themeAccent.opacity(0.2) : Color.gray.opacity(0.1), lineWidth: 20).frame(width: 250, height: 250); VStack { Text(viewModel.timeString(time: viewModel.seconds)).font(.system(size: 50, weight: .bold, design: .monospaced)); Text(viewModel.isTracking ? viewModel.t("กำลังโฟกัส...", "Focusing...") : viewModel.t("พร้อมเริ่มเรียน", "Ready to start")).foregroundColor(.gray) } }.padding(.top, 20)
                    
                    HStack(spacing: 15) {
                        if !viewModel.isTracking && viewModel.seconds == 0 { Button(action: { viewModel.toggleTracking() }) { Text(viewModel.t("▶️ เริ่มเรียน", "▶️ Start")).font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(viewModel.themeAccent).cornerRadius(15) } }
                        else {
                            Button(action: { viewModel.toggleTracking() }) { Text(viewModel.isTracking ? viewModel.t("⏸️ พักชั่วคราว", "⏸️ Pause") : viewModel.t("▶️ ทำต่อ", "▶️ Resume")).font(.headline).frame(maxWidth: .infinity).padding().background(Color.gray.opacity(0.2)).cornerRadius(15) }
                            Button(action: { viewModel.saveSession() }) { Text(viewModel.t("⏹️ จบการเรียน", "⏹️ Stop")).font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(Color.red).cornerRadius(15) }
                        }
                    }.padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading) {
                            HStack { Text(viewModel.t("📚 1. เลือกวิชา", "📚 1. Select Subject")).font(.headline); Spacer(); Button(action: { showAddSubject.toggle() }) { Image(systemName: "plus.circle.fill").foregroundColor(viewModel.themeAccent); Text(viewModel.t("เพิ่มวิชา", "Add")).font(.subheadline) } }
                            if showAddSubject { HStack { TextField(viewModel.t("พิมพ์ชื่อวิชาใหม่...", "Type subject name..."), text: $newSubjectText).textFieldStyle(RoundedBorderTextFieldStyle()); Button(viewModel.t("ตกลง", "OK")) { viewModel.addNewSubject(newSubjectText); newSubjectText = ""; showAddSubject = false }.padding(.horizontal, 10).padding(.vertical, 5).background(viewModel.themeAccent).foregroundColor(.white).cornerRadius(8) }.padding(.bottom, 5) }
                            Picker(viewModel.t("เลือกวิชา", "Select"), selection: $viewModel.selectedSubject) { ForEach(viewModel.subjects, id: \.self) { Text($0) } }.pickerStyle(MenuPickerStyle()).padding().frame(maxWidth: .infinity, alignment: .leading).background(viewModel.themeCardBg).cornerRadius(12).shadow(color: .black.opacity(0.05), radius: 2).disabled(viewModel.isTracking)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(viewModel.t("🎯 2. เลือกลิงก์กับแผนการอ่าน", "🎯 2. Link to Plan")).font(.headline)
                            Picker(viewModel.t("เลือกแผน", "Select Plan"), selection: $viewModel.selectedPlanId) {
                                Text(viewModel.t("ไม่ผูกกับแผน (จับเวลาลอยๆ)", "Don't link to plan")).tag(UUID?(nil))
                                let subjectPlans = viewModel.studyPlans.filter { $0.subject == viewModel.selectedSubject && !$0.isCompleted }
                                ForEach(subjectPlans) { plan in Text("\(plan.title) (\(String(format: "%.1f", plan.targetHours)) \(viewModel.t("ชม.", "h")) )").tag(UUID?(plan.id)) }
                            }
                            .pickerStyle(MenuPickerStyle()).padding().frame(maxWidth: .infinity, alignment: .leading).background(viewModel.themeCardBg).cornerRadius(12).shadow(color: .black.opacity(0.05), radius: 2).disabled(viewModel.isTracking)
                            .onChange(of: viewModel.selectedPlanId) { newId in
                                if let id = newId, let plan = viewModel.studyPlans.first(where: { $0.id == id }) { viewModel.selectedTags = [plan.activityTag] }
                            }
                            
                            if let planId = viewModel.selectedPlanId, let plan = viewModel.studyPlans.first(where: { $0.id == planId }) {
                                let tracked = Double(plan.trackedSeconds) / 3600.0
                                let progress = plan.targetHours > 0 ? min(tracked / plan.targetHours, 1.0) : 0
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(viewModel.t("ความคืบหน้า:", "Progress:")).font(.caption).foregroundColor(.gray); Spacer(); Text("\(String(format: "%.2f", tracked)) / \(String(format: "%.1f", plan.targetHours)) \(viewModel.t("ชม.", "h"))").font(.caption).fontWeight(.bold).foregroundColor(plan.isCompleted ? .green : viewModel.themeAccent) }
                                    ProgressView(value: progress).tint(plan.isCompleted ? .green : viewModel.themeAccent)
                                }.padding(.top, 10)
                            }
                        }
                        
                        VStack(alignment: .leading) {
                            Text(viewModel.t("🏷️ 3. รูปแบบกิจกรรม", "🏷️ 3. Activity Tag")).font(.headline)
                            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(MOCK_TAGS) { tag in let isSelected = viewModel.selectedTags.contains(tag.id); Button(action: { if isSelected { viewModel.selectedTags.remove(tag.id) } else { viewModel.selectedTags.insert(tag.id) } }) { Text(viewModel.language == .thai ? tag.labelTh : tag.labelEn).font(.subheadline).fontWeight(isSelected ? .bold : .regular).padding(.horizontal, 16).padding(.vertical, 8).background(isSelected ? tag.color : Color.gray.opacity(0.1)).foregroundColor(isSelected ? .white : .primary).cornerRadius(20) }.disabled(viewModel.isTracking) } }.padding(.vertical, 5) }
                        }
                    }.padding().background(Color.gray.opacity(0.05)).cornerRadius(20).padding(.horizontal)
                }.padding(.bottom, 40)
            }
        }
    }
}

// MARK: - 2. Calendar / Dashboard View
struct CalendarView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showAddPlan = false
    @State private var planTitle = ""
    @State private var planSubject = ""
    @State private var planDate = Date()
    @State private var hasDeadline = false
    @State private var planDeadline = Date()
    @State private var planTargetHours: Double = 1.0
    @State private var planActivityTag: String = "theory"
    @State private var showingEmergencyAlert = false
    
    let columns = [GridItem(.adaptive(minimum: 150), spacing: 15)]
    
    var body: some View {
        NavigationView {
            ZStack {
                viewModel.themeBg.edgesIgnoringSafeArea(.all)
                ScrollView {
                    VStack(alignment: .leading) {
                        Text(viewModel.t("เลือกวิชาเพื่อดูรายละเอียด และกำหนดการสอบ", "Select a subject to view details and exams"))
                            .font(.subheadline).foregroundColor(.gray).padding(.horizontal)
                        
                        LazyVGrid(columns: columns, spacing: 15) {
                            ForEach(viewModel.subjects, id: \.self) { subject in
                                NavigationLink(destination: SubjectDetailView(viewModel: viewModel, subject: subject)) {
                                    SubjectBoxView(viewModel: viewModel, subject: subject)
                                }.buttonStyle(PlainButtonStyle())
                            }
                        }.padding()
                    }
                }
            }
            .navigationTitle(viewModel.t("แผนแยกรายวิชา", "Dashboard"))
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: {
                        if !viewModel.studyPlans.filter({ !$0.isCompleted }).isEmpty { showingEmergencyAlert = true }
                    }) { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange) }
                    .alert(isPresented: $showingEmergencyAlert) {
                        Alert(title: Text(viewModel.t("ให้ AI ช่วยจัดตารางใหม่ไหม?", "Let AI reschedule?")), message: Text(viewModel.t("ระบบจะส่งรายการที่ยังไม่เสร็จไปให้ AI เกลี่ยเวลาให้ใหม่ ยืนยันหรือไม่?", "Unfinished tasks will be sent to AI for rescheduling. Confirm?")), primaryButton: .default(Text(viewModel.t("ยืนยัน", "Confirm"))) { viewModel.emergencyRescheduleWithAI() }, secondaryButton: .cancel(Text(viewModel.t("ยกเลิก", "Cancel"))))
                    }
                    Button(action: { planSubject = viewModel.subjects.first ?? ""; showAddPlan = true }) { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddPlan) {
                NavigationView {
                    Form {
                        Section(header: Text(viewModel.t("รายละเอียดเนื้อหา", "Details"))) {
                            TextField(viewModel.t("ชื่อบทเรียน", "Topic"), text: $planTitle)
                            Picker(viewModel.t("วิชา", "Subject"), selection: $planSubject) { ForEach(viewModel.subjects, id: \.self) { Text($0) } }
                            Picker(viewModel.t("รูปแบบ", "Tag"), selection: $planActivityTag) { ForEach(MOCK_TAGS) { tag in Text(viewModel.language == .thai ? tag.labelTh : tag.labelEn).tag(tag.id) } }
                            Stepper(viewModel.t("เป้าหมาย: \(String(format: "%.1f", planTargetHours)) ชม.", "Target: \(String(format: "%.1f", planTargetHours)) h"), value: $planTargetHours, in: 0.5...10.0, step: 0.5)
                        }
                        
                        Section(header: Text(viewModel.t("กำหนดเวลา (แจ้งเตือนล่วงหน้า)", "Time (With Notifications)"))) {
                            DatePicker("📅 " + viewModel.t("เวลาอ่าน", "Study Time"), selection: $planDate, displayedComponents: [.date, .hourAndMinute])
                            Toggle("⏰ " + viewModel.t("มีกำหนดส่ง/สอบย่อย", "Has Deadline"), isOn: $hasDeadline)
                            if hasDeadline { DatePicker(viewModel.t("เลือก Deadline", "Select Deadline"), selection: $planDeadline, displayedComponents: .date).foregroundColor(.red) }
                        }
                    }
                    .navigationTitle(viewModel.t("เพิ่มแผน", "Add Plan"))
                    .navigationBarItems(
                        leading: Button(viewModel.t("ยกเลิก", "Cancel")) { showAddPlan = false },
                        trailing: Button(viewModel.t("บันทึก", "Save")) {
                            if !planTitle.isEmpty {
                                let finalDl = hasDeadline ? planDeadline : nil
                                viewModel.addNewPlan(title: planTitle, subject: planSubject, date: planDate, deadline: finalDl, targetHours: planTargetHours, activityTag: planActivityTag)
                                planTitle = ""; hasDeadline = false; planTargetHours = 1.0; showAddPlan = false
                            }
                        }.disabled(planTitle.isEmpty)
                    )
                }
            }
        }
    }
}

struct SubjectBoxView: View {
    @ObservedObject var viewModel: AppViewModel
    let subject: String
    var plans: [StudyPlan] { viewModel.studyPlans.filter { $0.subject == subject } }
    var examDate: Date? { viewModel.subjectExams[subject] }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(subject).font(.headline).foregroundColor(.primary).lineLimit(1)
            
            if let exam = examDate {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.t("สอบใหญ่:", "Final Exam:")).font(.system(size: 10)).foregroundColor(.gray)
                    HStack { Image(systemName: "flag.checkered").foregroundColor(.red); Text(exam.formatted(.dateTime.day().month().year())).font(.caption).fontWeight(.bold).foregroundColor(.red) }
                }
            } else { Text(viewModel.t("ยังไม่กำหนดวันสอบ", "No exam set")).font(.caption).foregroundColor(.gray) }
            
            Spacer()
            
            let completed = plans.filter { $0.isCompleted }.count
            let total = plans.count
            
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: total > 0 ? Double(completed)/Double(total) : 0).tint(completed == total && total > 0 ? .green : viewModel.themeAccent)
                Text("\(completed)/\(total) \(viewModel.t("บทเรียน", "tasks"))").font(.caption2).foregroundColor(.gray)
            }
        }
        .padding().frame(height: 140).frame(maxWidth: .infinity, alignment: .leading).background(viewModel.themeCardBg).cornerRadius(15).shadow(color: .black.opacity(0.05), radius: 5)
    }
}

struct SubjectDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    let subject: String
    @State private var showExamPicker = false
    @State private var tempExamDate = Date()
    @State private var showingDeleteAlert = false
    
    var subjectPlans: [StudyPlan] { viewModel.studyPlans.filter { $0.subject == subject }.sorted { $0.date < $1.date } }
    
    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("🚨 \(viewModel.t("วันสอบวิชา", "Exam Date for")) \(subject)").font(.caption).foregroundColor(.gray)
                    if let exam = viewModel.subjectExams[subject] { Text(exam.formatted(date: .long, time: .omitted)).font(.headline).foregroundColor(.red) } else { Text(viewModel.t("ยังไม่ได้ตั้งค่า", "Not set")).font(.headline).foregroundColor(.gray) }
                }
                Spacer()
                Button(action: { tempExamDate = viewModel.subjectExams[subject] ?? Date(); showExamPicker.toggle() }) {
                    Text(viewModel.t("ตั้งค่าวันสอบ", "Set Exam")).font(.caption).fontWeight(.bold).padding(8).background(viewModel.themeAccent.opacity(0.1)).foregroundColor(viewModel.themeAccent).cornerRadius(8)
                }
            }.padding().background(viewModel.themeCardBg).cornerRadius(15).shadow(color: .black.opacity(0.05), radius: 3).padding()
            
            List {
                if subjectPlans.isEmpty { Text(viewModel.t("ยังไม่มีแผนอ่านสำหรับวิชานี้", "No study plans for this subject yet.")).foregroundColor(.gray) }
                ForEach(subjectPlans) { plan in
                    NavigationLink(destination: PlanDetailView(viewModel: viewModel, plan: plan, subjectExamDate: viewModel.subjectExams[subject])) {
                        HStack {
                            Image(systemName: plan.isCompleted ? "checkmark.circle.fill" : "circle").foregroundColor(plan.isCompleted ? .green : .gray).font(.title3)
                            
                            VStack(alignment: .leading, spacing: 5) {
                                Text(plan.title).font(.headline).strikethrough(plan.isCompleted).foregroundColor(plan.isCompleted ? .gray : .primary)
                                let tag = MOCK_TAGS.first(where: { $0.id == plan.activityTag })
                                Text("\(viewModel.language == .thai ? (tag?.labelTh ?? "") : (tag?.labelEn ?? "")) (\(String(format: "%.1f", plan.targetHours)) \(viewModel.t("ชม.", "h")))")
                                    .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(plan.isCompleted ? Color.gray.opacity(0.2) : (tag?.color.opacity(0.1) ?? viewModel.themeAccent.opacity(0.1)))
                                    .foregroundColor(plan.isCompleted ? .gray : (tag?.color ?? viewModel.themeAccent)).cornerRadius(4)
                                
                                let trackedHours = Double(plan.trackedSeconds) / 3600.0
                                let progress = plan.targetHours > 0 ? min(trackedHours / plan.targetHours, 1.0) : 0.0
                                ProgressView(value: progress).tint(plan.isCompleted ? .green : (tag?.color ?? .blue))
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                if let deadline = plan.deadline { HStack { Image(systemName: "exclamationmark.circle.fill").font(.caption2).foregroundColor(.red); Text(deadline, style: .date).font(.caption).foregroundColor(.red) } }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                .onDelete { indexSet in for index in indexSet { viewModel.deletePlan(plan: subjectPlans[index]) } }
            }
        }
        .navigationTitle(subject).background(viewModel.themeBg.edgesIgnoringSafeArea(.all))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingDeleteAlert = true }) { Image(systemName: "trash.slash.fill").foregroundColor(.red) }
                .alert(isPresented: $showingDeleteAlert) { Alert(title: Text(viewModel.t("ลบ Deadline ย่อยทั้งหมด?", "Delete all sub-deadlines?")), message: Text(viewModel.t("วันกำหนดส่งงานย่อยจะถูกลบทั้งหมด แน่ใจไหม?", "All sub-deadlines will be removed. Are you sure?")), primaryButton: .destructive(Text(viewModel.t("ลบ", "Delete"))) { viewModel.deleteAllDeadlines(for: subject) }, secondaryButton: .cancel(Text(viewModel.t("ยกเลิก", "Cancel")))) }
            }
        }
        .sheet(isPresented: $showExamPicker) {
            NavigationView {
                VStack { DatePicker(viewModel.t("เลือกวันสอบ", "Select Date"), selection: $tempExamDate, displayedComponents: .date).datePickerStyle(.graphical).padding(); Spacer() }
                .navigationTitle(viewModel.t("กำหนดวันสอบใหญ่", "Set Final Exam")).navigationBarItems(leading: Button(viewModel.t("ยกเลิก", "Cancel")) { showExamPicker = false }, trailing: Button(viewModel.t("บันทึก", "Save")) { viewModel.subjectExams[subject] = tempExamDate; showExamPicker = false })
            }
        }
    }
}

struct PlanDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    let plan: StudyPlan
    let subjectExamDate: Date?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack { Image(systemName: plan.isCompleted ? "checkmark.seal.fill" : "hourglass"); Text(plan.isCompleted ? viewModel.t("อ่านเนื้อหานี้จบแล้ว!", "Task Completed!") : viewModel.t("ยังไม่ได้อ่านเนื้อหานี้", "Pending Task")) }
                .font(.headline).foregroundColor(plan.isCompleted ? .green : .orange).padding().frame(maxWidth: .infinity).background(plan.isCompleted ? Color.green.opacity(0.1) : Color.orange.opacity(0.1)).cornerRadius(15)

                VStack(alignment: .leading, spacing: 15) {
                    let tag = MOCK_TAGS.first(where: { $0.id == plan.activityTag })
                    let tagLabel = viewModel.language == .thai ? (tag?.labelTh ?? "") : (tag?.labelEn ?? "")
                    DetailRow(icon: "book.fill", title: "\(viewModel.t("วิชา", "Subject")) (\(tagLabel))", value: plan.subject, color: viewModel.themeAccent)
                    Divider()
                    DetailRow(icon: "calendar.badge.clock", title: viewModel.t("วันที่นัดตัวเองอ่าน (มีแจ้งเตือน)", "Scheduled Date (Notified)"), value: plan.date.formatted(date: .long, time: .shortened), color: .blue)
                    
                    if let deadline = plan.deadline { Divider(); DetailRow(icon: "exclamationmark.triangle.fill", title: "Deadline", value: deadline.formatted(date: .long, time: .omitted), color: .orange) }
                    if let exam = subjectExamDate { Divider(); DetailRow(icon: "flag.checkered", title: viewModel.t("วันสอบใหญ่", "Final Exam"), value: exam.formatted(date: .long, time: .omitted), color: .red) }
                }.padding().background(viewModel.themeCardBg).cornerRadius(15).shadow(color: .black.opacity(0.05), radius: 5)

                Button(action: { if let index = viewModel.studyPlans.firstIndex(where: { $0.id == plan.id }) { viewModel.studyPlans[index].isCompleted.toggle() } }) { Text(plan.isCompleted ? viewModel.t("ยกเลิกการติ๊กถูก", "Mark as Incomplete") : viewModel.t("บันทึกว่าอ่านจบแล้ว", "Mark as Completed")).font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(plan.isCompleted ? Color.gray : Color.green).cornerRadius(15) }
                Button(action: { viewModel.deletePlan(plan: plan) }) { HStack { Image(systemName: "trash.fill"); Text(viewModel.t("ลบแผนการเรียนนี้", "Delete this plan")) }.font(.headline).foregroundColor(.red).frame(maxWidth: .infinity).padding().background(Color.red.opacity(0.1)).cornerRadius(15) }.padding(.top, 10)
            }.padding()
        }.navigationTitle(plan.title).background(viewModel.themeBg.edgesIgnoringSafeArea(.all))
    }
}

struct DetailRow: View {
    let icon: String, title: String, value: String, color: Color
    var body: some View { HStack { Image(systemName: icon).foregroundColor(color).frame(width: 30); VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundColor(.gray); Text(value).font(.subheadline).fontWeight(.bold).foregroundColor(.primary) }; Spacer() } }
}

// MARK: - 3. Analytics View
struct AnalyticsView: View {
    @ObservedObject var viewModel: AppViewModel
    var totalHours: Double { viewModel.weeklyStats.reduce(0) { $0 + $1.hours } }
    var averageHours: Double { totalHours / 7.0 }
    var maxDayStat: DailyStat? { viewModel.weeklyStats.filter { $0.hours > 0 }.max(by: { $0.hours < $1.hours }) }
    var body: some View {
        NavigationView {
            ZStack {
                viewModel.themeBg.edgesIgnoringSafeArea(.all)
                ScrollView {
                    VStack(spacing: 20) {
                        Picker("Chart Style", selection: $viewModel.selectedChartStyle) { ForEach(ChartStyle.allCases) { style in Text(String(describing: style)).tag(style) } }.pickerStyle(SegmentedPickerStyle()).padding(.horizontal)
                        HStack { VStack(alignment: .leading, spacing: 5) { Text(viewModel.t("สัปดาห์นี้เรียนไปแล้ว", "Studied this week")).font(.subheadline).foregroundColor(viewModel.themeAccent); HStack(alignment: .firstTextBaseline) { Text(String(format: "%.1f", totalHours)).font(.system(size: 45, weight: .bold)); Text(viewModel.t("ชั่วโมง", "Hours")).font(.title3).foregroundColor(.gray) } }; Spacer(); Image(systemName: "clock.badge.checkmark").font(.system(size: 40)).foregroundColor(viewModel.themeAccent.opacity(0.3)) }.padding().background(viewModel.themeCardBg).cornerRadius(20).shadow(color: .black.opacity(0.05), radius: 5).padding(.horizontal)
                        HStack(spacing: 15) {
                            VStack(alignment: .leading, spacing: 8) { HStack { Image(systemName: "chart.line.uptrend.xyaxis").foregroundColor(.blue); Text(viewModel.t("เฉลี่ยต่อวัน", "Daily Avg.")).font(.caption).foregroundColor(.gray) }; Text(String(format: "%.1f ", averageHours) + viewModel.t("ชม.", "h")).font(.title2).fontWeight(.bold).foregroundColor(.primary) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(viewModel.themeCardBg).cornerRadius(15).shadow(color: .black.opacity(0.05), radius: 5)
                            VStack(alignment: .leading, spacing: 8) { HStack { Image(systemName: "flame.fill").foregroundColor(.orange); Text(viewModel.t("ท็อปฟอร์ม", "Top Form")).font(.caption).foregroundColor(.gray) }; Text(maxDayStat != nil ? "\(maxDayStat!.day)" : "-").font(.title2).fontWeight(.bold).foregroundColor(.primary) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(viewModel.themeCardBg).cornerRadius(15).shadow(color: .black.opacity(0.05), radius: 5)
                        }.padding(.horizontal)
                        VStack(alignment: .leading) {
                            Text(String(describing: viewModel.selectedChartStyle)).font(.headline).foregroundColor(viewModel.themeAccent).padding(.bottom, 10)
                            Chart { ForEach(viewModel.weeklyStats) { stat in switch viewModel.selectedChartStyle { case .bar: BarMark(x: .value("Day", stat.day), y: .value("Hours", stat.hours)).foregroundStyle(viewModel.themeAccent.gradient).cornerRadius(5)
                            case .line: LineMark(x: .value("Day", stat.day), y: .value("Hours", stat.hours)).foregroundStyle(viewModel.themeAccent).interpolationMethod(.catmullRom)
                            case .point: PointMark(x: .value("Day", stat.day), y: .value("Hours", stat.hours)).foregroundStyle(Color.orange).symbolSize(100)
                            case .pie: SectorMark(angle: .value("Hours", stat.hours), angularInset: 1).foregroundStyle(by: .value("Day", stat.day)).cornerRadius(5) } } }.frame(height: 200).chartLegend(position: .bottom, alignment: .center, spacing: 15)
                        }.padding().background(viewModel.themeCardBg).cornerRadius(20).shadow(color: .black.opacity(0.05), radius: 5).padding(.horizontal)
                    }.padding(.vertical)
                }
            }
            .navigationTitle(viewModel.t("สถิติการเรียน", "Statistics"))
        }
    }
}

// MARK: - 4. Burnout View
struct BurnoutView: View {
    @ObservedObject var viewModel: AppViewModel
    var gaugeColor: Color { if viewModel.fatigueLevel > 80 { return .red } else if viewModel.fatigueLevel > 50 { return .orange } else { return .green } }
    var body: some View {
        ZStack {
            viewModel.themeBg.edgesIgnoringSafeArea(.all)
            ScrollView {
                VStack(spacing: 30) {
                    Text(viewModel.t("สถานะสมอง", "Brain Status")).font(.title2).fontWeight(.bold).padding(.top, 20)
                    ZStack {
                        Circle().stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 25, lineCap: .round)).frame(width: 220, height: 220)
                        Circle().trim(from: 0.0, to: CGFloat(min(viewModel.fatigueLevel / 100.0, 1.0))).stroke(gaugeColor, style: StrokeStyle(lineWidth: 25, lineCap: .round)).frame(width: 220, height: 220).rotationEffect(.degrees(-90)).animation(.easeInOut(duration: 1.0), value: viewModel.fatigueLevel)
                        VStack(spacing: 5) { Text(viewModel.t("ความล้า", "Fatigue")).font(.headline).foregroundColor(.gray); Text("\(Int(viewModel.fatigueLevel))%").font(.system(size: 60, weight: .black, design: .rounded)).foregroundColor(gaugeColor) }
                    }.padding(.vertical, 20)
                    Text(viewModel.t("เลือกวิธีการพักผ่อน เพื่อลดระดับความล้า", "Choose a rest method to reduce fatigue")).font(.subheadline).foregroundColor(.gray)
                    VStack(spacing: 15) {
                        RestButton(icon: "eye.slash.fill", title: viewModel.t("พักสายตาจากจอ", "Rest Eyes"), duration: "10m", recovery: 10.0, color: .blue) { viewModel.applyRest(recoveryPercentage: 10.0) }
                        RestButton(icon: "figure.walk", title: viewModel.t("ยืดเส้นยืดสาย / เดินเล่น", "Stretch / Walk"), duration: "15m", recovery: 15.0, color: .green) { viewModel.applyRest(recoveryPercentage: 15.0) }
                        RestButton(icon: "cup.and.saucer.fill", title: viewModel.t("ดื่มน้ำ / หาของว่าง", "Drink / Snack"), duration: "20m", recovery: 20.0, color: .orange) { viewModel.applyRest(recoveryPercentage: 20.0) }
                        RestButton(icon: "bed.double.fill", title: viewModel.t("งีบหลับ (Power Nap)", "Power Nap"), duration: "30m", recovery: 30.0, color: .purple) { viewModel.applyRest(recoveryPercentage: 30.0) }
                    }.padding(.horizontal)
                }.padding(.bottom, 40)
            }
        }
    }
}

struct RestButton: View {
    let icon: String, title: String, duration: String, recovery: Double, color: Color, action: () -> Void
    var body: some View { Button(action: action) { HStack(spacing: 15) { ZStack { Circle().fill(color.opacity(0.2)).frame(width: 50, height: 50); Image(systemName: icon).font(.title2).foregroundColor(color) }; VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline).foregroundColor(.primary); Text(duration).font(.caption).foregroundColor(.gray) }; Spacer(); VStack(alignment: .trailing) { Text("Recovery").font(.caption2).foregroundColor(.gray); Text("-\(Int(recovery))%").font(.headline).foregroundColor(.green) } }.padding().background(Color.gray.opacity(0.1)).cornerRadius(15) } }
}

// MARK: - 5. AI Assistant View
struct AIAssistantView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var inputText: String = ""
    @State private var showingFilePicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(viewModel.chatMessages) { message in
                            HStack {
                                if message.isUser { Spacer() }
                                if message.isFile {
                                    HStack { Image(systemName: "doc.text.fill").foregroundColor(.white).font(.title2); Text(message.text).fontWeight(.medium) }.padding(12).background(Color.blue).foregroundColor(.white).cornerRadius(15).shadow(color: Color.black.opacity(0.05), radius: 3, y: 2)
                                } else {
                                    Text(message.text).padding(12).background(message.isUser ? viewModel.themeAccent : viewModel.themeCardBg).foregroundColor(message.isUser ? .white : .primary).cornerRadius(15).shadow(color: Color.black.opacity(0.05), radius: 3, y: 2)
                                }
                                if !message.isUser { Spacer() }
                            }
                        }
                        if viewModel.isAITyping { HStack { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: viewModel.themeAccent)); Text(viewModel.t("กำลังคิด...", "Thinking...")).font(.caption).foregroundColor(.gray).padding(.leading, 5); Spacer() } }
                    }.padding().onChange(of: viewModel.chatMessages.count) { _ in if let lastId = viewModel.chatMessages.last?.id { withAnimation { proxy.scrollTo(lastId, anchor: .bottom) } } }
                }
            }.background(viewModel.themeBg)
            
            HStack(spacing: 10) {
                Button(action: { showingFilePicker = true }) { Image(systemName: "paperclip").font(.system(size: 20)).foregroundColor(.gray).padding(10).background(Color.gray.opacity(0.15)).clipShape(Circle()) }.disabled(viewModel.isAITyping)
                TextField(viewModel.t("บอก AI หรือแนบไฟล์...", "Ask AI or attach file..."), text: $inputText).padding(12).background(Color.gray.opacity(0.1)).cornerRadius(20).disabled(viewModel.isAITyping)
                Button(action: { viewModel.askAI(message: inputText); inputText = "" }) { Image(systemName: "paperplane.fill").foregroundColor(.white).padding(12).background(inputText.isEmpty || viewModel.isAITyping ? Color.gray : viewModel.themeAccent).clipShape(Circle()) }.disabled(inputText.isEmpty || viewModel.isAITyping)
            }.padding().background(viewModel.themeCardBg)
        }
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.pdf, .plainText, .image, .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): guard let url = urls.first else { return }; viewModel.askAI(message: "\(url.lastPathComponent)", isEmergency: false, isFile: true)
            case .failure(let error): print("Error: \(error.localizedDescription)")
            }
        }
    }
}
