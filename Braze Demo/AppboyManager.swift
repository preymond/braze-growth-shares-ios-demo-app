import UIKit
import Appboy_iOS_SDK
import AdSupport
import AppTrackingTransparency

class AppboyManager: NSObject {
  static let shared = AppboyManager()
#warning("Please enter your API key below")
  private let apiKey = "YOUR-API-KEY"
#warning("Please enter your API key above")
  private var appboyOptions: [String: Any] {
    return [ABKIDFADelegateKey: AppboyIDFADelegate(), ABKMinimumTriggerTimeIntervalKey: 0]
  }
  
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?){
        
    Appboy.start(withApiKey: apiKey, in: application, withLaunchOptions: launchOptions, withAppboyOptions: appboyOptions)
    
    let options: UNAuthorizationOptions = [.alert, .sound, .badge]
    
    /// This is how to include provisional push support
    // options = UNAuthorizationOptions(rawValue: options.rawValue | UNAuthorizationOptions.provisional.rawValue)
    
    UNUserNotificationCenter.current().requestAuthorization(options: options) { (granted, error) in
      Appboy.sharedInstance()?.pushAuthorization(fromUserNotificationCenter: granted)
    }
    UIApplication.shared.registerForRemoteNotifications()
    
    Appboy.sharedInstance()?.inAppMessageController.inAppMessageUIController?.setInAppMessageUIDelegate?(self)
  }
  
  /// Initialized as the value for the ABKIDFADelegateKey.
  private class AppboyIDFADelegate: NSObject, ABKIDFADelegate {
    func advertisingIdentifierString() -> String {
      return ASIdentifierManager.shared().advertisingIdentifier.uuidString
    }

    func isAdvertisingTrackingEnabledOrATTAuthorized() -> Bool {
      return ATTrackingManager.trackingAuthorizationStatus ==  ATTrackingManager.AuthorizationStatus.authorized
    }
  }
}

// MARK: - User
extension AppboyManager {
  var userId: String? {
     return Appboy.sharedInstance()?.user.userID
   }
    
  func changeUser(_ userId: String) {
    Appboy.sharedInstance()?.changeUser(userId)
  }
}

// MARK: - Push
extension AppboyManager {
  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Appboy.sharedInstance()?.registerDeviceToken(deviceToken)
  }
  
  ///Remote notifications are set up in this demo to show how silent push can be used in conjunction with Content Cards to influence the UI/UX of the application.
  func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    Appboy.sharedInstance()?.register(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
    
    if let updateHomeTo = userInfo["refresh_home"] as? String {
      switch updateHomeTo {
      case "Default":
        RemoteStorage().removeObject(forKey: .homeListPriority)
        NotificationCenter.default.post(name: .defaultAppExperience, object: nil)
      case "Content Card":
        NotificationCenter.default.post(name: .homeScreenContentCard, object: nil)
      default:
        break
      }
    }
      
    if let priority = userInfo["home_tile_priority"] as? String {
      RemoteStorage().store(priority, forKey: .homeListPriority)
      if userInfo["refresh_home"] == nil {
        NotificationCenter.default.post(name: .reorderHomeScreen, object: nil)
      }
    }
    
    if let eventName = userInfo["event_name"] as? String {
      logCustomEvent(eventName)
    }
  }
  
  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    Appboy.sharedInstance()?.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }
}

// MARK: - Analytics
extension AppboyManager {
  func logCustomEvent(_ eventName: String, withProperties properties: [AnyHashable: Any]? = nil) {
    Appboy.sharedInstance()?.logCustomEvent(eventName, withProperties: properties)
  }
  
  func setCustomAttributeWithKey(_ key: String?, andStringValue value: String?) {
    guard let key = key, let value = value else { return }
    Appboy.sharedInstance()?.user.setCustomAttributeWithKey(key, andStringValue: value)
  }
  
  func setCustomAttributeWithKey(_ key: String?, andArrayValue value: [Any]?) {
    guard let key = key, let value = value else { return }
    Appboy.sharedInstance()?.user.setCustomAttributeArrayWithKey(key, array: value)
  }
  
  func logPurchase(productIdentifier: String, inCurrency currency: String, atPrice price: String, withQuanitity quanity: Int) {
    Appboy.sharedInstance()?.logPurchase(productIdentifier, inCurrency: currency, atPrice: NSDecimalNumber(string: price), withQuantity: UInt(quanity))
  }
}

// MARK: - In-App Messages
extension AppboyManager {
  func isInAppMessageSlideFromTop(_ inAppMessage: ABKInAppMessage) -> Bool {
    guard let slideup = inAppMessage as? ABKInAppMessageSlideup else { return false }
    return slideup.inAppMessageSlideupAnchor == .fromTop
  }
}

// MARK: - ABKInAppMessage UI Delegate
extension AppboyManager: ABKInAppMessageUIDelegate {
  func inAppMessageViewControllerWith(_ inAppMessage: ABKInAppMessage) -> ABKInAppMessageViewController {
    switch inAppMessage {
    case is ABKInAppMessageSlideup:
      return slideupViewController(inAppMessage: inAppMessage)
    case is ABKInAppMessageModal:
      return modalViewController(inAppMessage: inAppMessage)
    case is ABKInAppMessageFull:
      return fullViewController(inAppMessage: inAppMessage)
    case is ABKInAppMessageHTML:
      return ABKInAppMessageHTMLViewController(inAppMessage: inAppMessage)
    case is ABKInAppMessageImmersive:
      return ABKInAppMessageImmersiveViewController(inAppMessage: inAppMessage)
    default:
      return ABKInAppMessageViewController(inAppMessage: inAppMessage)
    }
  }
}

// MARK: - Content Cards
extension AppboyManager {
  var contentCards: [ABKContentCard]? {
    return Appboy.sharedInstance()?.contentCardsController.contentCards as? [ABKContentCard]
  }
  
  /// Registers an observer to the Content Card Processed Appboy dependent Notification.
  /// - parameter observer: The listener of the `ABKContentCardsProcessed Notification`.
  /// - parameter selector: The method specified by selector must have one and only one argument (an instance of Notification).
  func addObserverForContentCards(observer: Any, selector: Selector) {
    NotificationCenter.default.addObserver(observer, selector: selector,
    name:NSNotification.Name.ABKContentCardsProcessed, object: nil)
  }
  
  func requestContentCardsRefresh() {
    Appboy.sharedInstance()?.requestContentCardsRefresh()
  }
  
  /// Parses the Appboy dependent information from `Notification.userInfo` dictionary and converts the `ABKContentCard` objects into `ContentCardable` objects.
  /// - parameter notification: A container for information broadcast through a notification center to all registered observers.
  /// - parameter classTypes: The filter to determine what custom objects to be returned
  func handleContentCardsUpdated(_ notification: Notification, for classTypes: [ContentCardClassType]) -> [ContentCardable] {
    guard let updateIsSuccessful = notification.userInfo?[ABKContentCardsProcessedIsSuccessfulKey] as? Bool, updateIsSuccessful, let cards = contentCards else { return [] }
            
    return convertContentCards(cards, for: classTypes)
  }
  
  /// Logs an` ABKContentCard` clicked.
  /// - parameter idString: Identifier used to retrieve an ABKContentCard.
  func logContentCardClicked(idString: String?) {
    guard let contentCard = getContentCard(forString: idString) else { return }
    
    contentCard.logContentCardClicked()
  }
  
  /// Logs an` ABKContentCard` impression.
  /// - parameter idString: Identifier used to retrieve an ABKContentCard.
  func logContentCardImpression(idString: String?) {
    guard let contentCard = getContentCard(forString: idString) else { return }
    
    contentCard.logContentCardImpression()
  }
  
  /// Logs an `ABKContentCard` dismissed.
  /// - parameter idString: Identifier used to retrieve an ABKContentCard.
  func logContentCardDismissed(idString: String?) {
    guard let contentCard = getContentCard(forString: idString) else { return }
    
    contentCard.logContentCardDismissed()
  }
  
  /// Retrieves an `ABKContentCard` from the `Appboy.sharedInstance()?.contentCardsController.contentCards` array.
  /// - parameter idString: Identifier used to retrieve an ABKContentCard.
  private func getContentCard(forString idString: String?) -> ABKContentCard? {
    return contentCards?.first(where: { $0.idString == idString })
  }
}

// MARK: - Private Methods
private extension AppboyManager {
  /// Helper method to convert `ABKContentCard` objects to `ContentCardable` objects.
  ///
  /// The variables of `ABKContentCard` are parsed into a dictionary to be used as the `metaData` parameter for the `ContentCardable` initializer. All key-value pairs from the Braze dashboard are represented in the `extras` variable.
  ///
  /// The `ContentCardKey` is used to identify the values from each `ABKContentCard` variable.
  /// - parameter cards: Array of Content Cards.
  /// - parameter classTypes: Used to determine what Content Cards to convert. If a Content Card's classType does not match any of the classTypes, it will skip converting that `ABKContentCard`.
  func convertContentCards(_ cards: [ABKContentCard], for classTypes: [ContentCardClassType]) -> [ContentCardable] {
    var contentCardables: [ContentCardable] = []
    for card in cards {
      let classTypeString = card.extras?[ContentCardKey.classType.rawValue] as? String
      let classType = ContentCardClassType(rawType: classTypeString)
      guard classTypes.contains(classType) else { continue }
      
      var metaData: [ContentCardKey: Any] = [:]
      switch card {
      case is ABKBannerContentCard:
        let banner = card as! ABKBannerContentCard
        metaData[.image] = banner.image
      case is ABKCaptionedImageContentCard:
        let captioned = card as! ABKCaptionedImageContentCard
        metaData[.title] = captioned.title
        metaData[.cardDescription] = captioned.cardDescription
        metaData[.image] = captioned.image
      case is ABKClassicContentCard:
        let classic = card as! ABKClassicContentCard
        metaData[.title] = classic.title
        metaData[.cardDescription] = classic.cardDescription
        metaData[.image] = classic.image
      default:
        break
      }
      metaData[.idString] = card.idString
      metaData[.created] = card.created
      metaData[.dismissable] = card.dismissible
      metaData[.extras] = card.extras
     
      if let contentCardable = contentCardable(with: metaData, for: classType) {
        contentCardables.append(contentCardable)
      }
    }
    return contentCardables
  }
  
  /// Instantiates a custom object that confroms to the `ContentCardable` protocol.
  ///
  /// - parameter metaData: `Dictionary` used to instantiate the custom object.
  /// - parameter classType: Determines the custom object to instantiate.
  func contentCardable(with metaData: [ContentCardKey: Any], for classType: ContentCardClassType) -> ContentCardable? {
    switch classType {
    case .ad:
      return Ad(metaData: metaData, classType: classType)
    case .coupon:
      return Coupon(metaData: metaData, classType: classType)
    case .item(.tile):
      return Tile(metaData: metaData, classType: classType)
    case .message(.fullPage):
      return FullPageMessage(metaData: metaData, classType: classType)
    case .message(.webView):
      return WebViewMessage(metaData: metaData, classType: classType)
    default:
      return nil
    }
  }
}

// MARK: - Silent Push Notifcation Names
extension Notification.Name {
  static let defaultAppExperience = Notification.Name("kDefaultApExperience")
  static let homeScreenContentCard = Notification.Name("kHomeScreenContentCard")
  static let reorderHomeScreen = Notification.Name("kReorderHomeScreen")
}

// MARK: - Slideup In-App Message
class SlideupViewController: ABKInAppMessageSlideupViewController {}

// MARK: - Modal In-App Message
class ModalViewController: ABKInAppMessageModalViewController {
  
  // MARK: - Outlets
  @IBOutlet private weak var primaryButton: ABKInAppMessageUIButton!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    if let immersiveMessage = inAppMessage as? ABKInAppMessageImmersive, let buttons = immersiveMessage.buttons {
      switch buttons.count {
      case 1:
        primaryButton.titleLabel?.text = buttons[0].buttonText
      case 2:
        primaryButton.titleLabel?.text = buttons[1].buttonText
      default:
        break
      }
    }
  }
}

// MARK: - Full In-App Message
class FullViewController: ABKInAppMessageFullViewController {}

// MARK: - In-App Message View Controller Helpers
private extension AppboyManager {
  func slideupViewController(inAppMessage: ABKInAppMessage) -> ABKInAppMessageSlideupViewController {
    if isInAppMessageSlideFromTop(inAppMessage) {
      return ABKInAppMessageSlideupViewController(inAppMessage: inAppMessage)
    } else {
      return SlideFromBottomViewController(inAppMessage: inAppMessage)
    }
  }
  
  func modalViewController(inAppMessage: ABKInAppMessage) -> ABKInAppMessageModalViewController {
    switch inAppMessage.extras?[InAppMessageKey.viewType.rawValue] as? String {
    case InAppMessageViewType.picker.rawValue:
      return ModalPickerViewController(inAppMessage: inAppMessage)
    default:
      return ABKInAppMessageModalViewController(inAppMessage: inAppMessage)
    }
  }
  
  func fullViewController(inAppMessage: ABKInAppMessage) -> ABKInAppMessageFullViewController {
    switch inAppMessage.extras?[InAppMessageKey.viewType.rawValue] as? String {
    case InAppMessageViewType.tableList.rawValue:
      return FullListViewController(inAppMessage: inAppMessage)
    default:
      return ABKInAppMessageFullViewController(inAppMessage: inAppMessage)
    }
  }
}
