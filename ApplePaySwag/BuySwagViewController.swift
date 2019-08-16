//
//  DetailViewController.swift
//  ApplePaySwag
//
//  Created by Erik.Kerber on 10/17/14.
//  Edited by Eric Cerney on 11/21/14.
//  Copyright (c) 2014 Razeware LLC. All rights reserved.
//

import UIKit
import PassKit

class BuySwagViewController: UIViewController {

    let SupportedPaymentNetworks = [PKPaymentNetworkVisa, PKPaymentNetworkMasterCard, PKPaymentNetworkAmex]
    let ApplePaySwagMerchantID = "merchant.com.razeware.ApplePaySwag"//"<TODO - Your merchant ID>" // This should be <your> merchant ID

    @IBOutlet weak var applePayButton: UIButton!
    @IBOutlet weak var swagPriceLabel: UILabel!
    @IBOutlet weak var swagTitleLabel: UILabel!
    @IBOutlet weak var swagImage: UIImageView!
    
    var swag: Swag! {
        didSet {
            // Update the view.
            self.configureView()
        }
    }

    func configureView() {

        if (!self.isViewLoaded()) {
            return
        }
        
        self.title = swag.title
        self.swagPriceLabel.text = "$" + swag.priceString
        self.swagImage.image = swag.image
        self.swagTitleLabel.text = swag.description
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applePayButton.hidden = !PKPaymentAuthorizationViewController.canMakePaymentsUsingNetworks(SupportedPaymentNetworks)
        self.configureView()
    }

    @IBAction func purchase(sender: AnyObject) {
        
        let request = PKPaymentRequest()
        request.merchantIdentifier = ApplePaySwagMerchantID
        request.supportedNetworks = SupportedPaymentNetworks
        request.merchantCapabilities = PKMerchantCapability.Capability3DS
        request.countryCode = "US"
        request.currencyCode = "USD"
        
        request.paymentSummaryItems = calculateSummaryItemsFromSwag(swag)
        
        switch (swag.swagType) {
        case .Delivered:
            request.requiredShippingAddressFields = PKAddressField.PostalAddress
        case .Electronic:
            request.requiredShippingAddressFields = PKAddressField.Email
        }
        request.requiredShippingAddressFields = PKAddressField.All

        switch (swag.swagType) {
        case .Delivered(let method):
            var shippingMethods = [PKShippingMethod]()
            
            for shippingMethod in ShippingMethod.ShippingMethodOptions {
                let method = PKShippingMethod(label: shippingMethod.title, amount: shippingMethod.price)
                method.identifier = shippingMethod.title
                method.detail = shippingMethod.description
                shippingMethods.append(method)
            }
            
            request.shippingMethods = shippingMethods
        case .Electronic:
            break
        }
        
        let applePayController = PKPaymentAuthorizationViewController(paymentRequest: request)
        applePayController.delegate = self
        presentViewController(applePayController, animated: true, completion: nil)
    }
    
    func calculateSummaryItemsFromSwag(swag: Swag) -> [PKPaymentSummaryItem] {
        var summaryItems = [PKPaymentSummaryItem]()
        summaryItems.append(PKPaymentSummaryItem(label: swag.title, amount: swag.price))
        
        switch (swag.swagType) {
        case .Delivered(let method):
            summaryItems.append(PKPaymentSummaryItem(label: "Shipping", amount: method.price))
        case .Electronic:
            break
        }
        
        summaryItems.append(PKPaymentSummaryItem(label: "Razeware", amount: swag.total()))

        return summaryItems
    }
}

extension BuySwagViewController: PKPaymentAuthorizationViewControllerDelegate {
    func paymentAuthorizationViewController(controller: PKPaymentAuthorizationViewController!, didAuthorizePayment payment: PKPayment!, completion: ((PKPaymentAuthorizationStatus) -> Void)!) {

        // 1
        let shippingAddress = self.createShippingAddressFromRef(payment.shippingAddress)

        // 2
        Stripe.setDefaultPublishableKey("<your-publishable-key>")
        
        // 3
        STPAPIClient.sharedClient().createTokenWithPayment(payment) {
            (token, error) -> Void in
            
            if (error != nil) {
                NSLog("%@", error)
                completion(PKPaymentAuthorizationStatus.Failure)
                return
            }
            
            // 4
            let shippingAddress = self.createShippingAddressFromRef(payment.shippingAddress)
            
            // 5
            let url = NSURL(string: "http://<your ip address>:5000/pay")
            let request = NSMutableURLRequest(URL: url!)
            request.HTTPMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            // 6
            let body = ["stripeToken": token.tokenId,
                        "amount": self.swag.total().decimalNumberByMultiplyingBy(NSDecimalNumber(string: "100")),
                        "description": self.swag.title,
                        "shipping": [
                            "city": shippingAddress.City!,
                            "state": shippingAddress.State!,
                            "zip": shippingAddress.Zip!,
                            "firstName": shippingAddress.FirstName!,
                            "lastName": shippingAddress.LastName!]
            ]
            
            var error: NSError?
            request.HTTPBody = NSJSONSerialization.dataWithJSONObject(body, options: NSJSONWritingOptions(), error: &error)
            
            // 7
            NSURLConnection.sendAsynchronousRequest(request, queue: NSOperationQueue.mainQueue()) { (response, data, error) -> Void in
                if (error != nil) {
                    completion(PKPaymentAuthorizationStatus.Failure)
                } else {
                    completion(PKPaymentAuthorizationStatus.Success)
                }
            }
        }
    }
    
    func paymentAuthorizationViewControllerDidFinish(controller: PKPaymentAuthorizationViewController!) {
        controller.dismissViewControllerAnimated(true, completion: nil)
    }
    
    func createShippingAddressFromRef(address: ABRecord!) -> Address {
        var shippingAddress: Address = Address()
        
        shippingAddress.FirstName = ABRecordCopyValue(address, kABPersonFirstNameProperty)?.takeRetainedValue() as? String
        shippingAddress.LastName = ABRecordCopyValue(address, kABPersonLastNameProperty)?.takeRetainedValue() as? String
        
        let addressProperty : ABMultiValueRef = ABRecordCopyValue(address, kABPersonAddressProperty).takeUnretainedValue() as ABMultiValueRef
        if let dict : NSDictionary = ABMultiValueCopyValueAtIndex(addressProperty, 0).takeUnretainedValue() as? NSDictionary {
            shippingAddress.Street = dict[String(kABPersonAddressStreetKey)] as? String
            shippingAddress.City = dict[String(kABPersonAddressCityKey)] as? String
            shippingAddress.State = dict[String(kABPersonAddressStateKey)] as? String
            shippingAddress.Zip = dict[String(kABPersonAddressZIPKey)] as? String
        }
        
        return shippingAddress
    }
    
    func paymentAuthorizationViewController(controller: PKPaymentAuthorizationViewController!, didSelectShippingAddress address: ABRecord!, completion: ((PKPaymentAuthorizationStatus, [AnyObject]!, [AnyObject]!) -> Void)!) {
        let shippingAddress = createShippingAddressFromRef(address)
        
        switch (shippingAddress.State, shippingAddress.City, shippingAddress.Zip) {
        case (.Some(let state), .Some(let city), .Some(let zip)):
            completion(.Success, nil, nil)
        default:
            completion(.InvalidShippingPostalAddress, nil, nil)
        }
    }
    
    func paymentAuthorizationViewController(controller: PKPaymentAuthorizationViewController!, didSelectShippingMethod shippingMethod: PKShippingMethod!, completion: ((PKPaymentAuthorizationStatus, [AnyObject]!) -> Void)!) {
        let shippingMethod = ShippingMethod.ShippingMethodOptions.filter {(method) in method.title == shippingMethod.identifier}.first!
        swag.swagType = SwagType.Delivered(method: shippingMethod)
        completion(PKPaymentAuthorizationStatus.Success, calculateSummaryItemsFromSwag(swag))
    }
}

