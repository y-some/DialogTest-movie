//
//  ViewController.swift
//  DialogTest-movie
//
//  Created by Yasuyuki Someya on 2016/07/03.
//  Copyright © 2016年 Yasuyuki Someya. All rights reserved.
//

import UIKit
import JSQMessages
import Alamofire
import SwiftyJSON
import SVProgressHUD

class ViewController: JSQMessagesViewController {
    
    // MARK: Declaration
    
    var messages: [JSQMessage]?
    var incomingBubble: JSQMessagesBubbleImage!
    var outgoingBubble: JSQMessagesBubbleImage!
    var incomingAvatar: JSQMessagesAvatarImage!
    var outgoingAvatar: JSQMessagesAvatarImage!
    
    // APIリクエスト時に必要となるユニークなDialogID
    let DIALOG_ID = ""
    // WatsonDialogサービスのサービス資格情報
    let DIALOG_USER = ""
    let DIALOG_PASS = ""
    var conversationId: String = ""
    var clientId: String = ""
    
    // Natural Language Classifier(NLC)APIリクエスト時に必要となるユニークなClassifierId
    let CLASSIFIER_ID_TITLE = ""
    let CLASSIFIER_ID_STARRING = ""
    // WatsonNLCサービスのサービス資格情報
    let NLC_USER = ""
    let NLC_PASS = ""
    
    // WatsonのResponse文字列の中で、名前を表示させる固定文字列（この文字列を置換する）
    let REPLACE_STRING = "%NAME%"
    // WatsonDialogの変数名
    let DIALOG_VAR_TITLE = "TITLE"
    let DIALOG_VAR_STARRING = "STARRING"
    
    // MARK: Event
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 自分のsenderId, senderDisokayNameを設定
        self.senderId = "user1"
        self.senderDisplayName = "hoge"
        
        // 吹き出しの設定
        let bubbleFactory = JSQMessagesBubbleImageFactory()
        self.incomingBubble = bubbleFactory.incomingMessagesBubbleImageWithColor(UIColor.jsq_messageBubbleBlueColor())
        self.outgoingBubble = bubbleFactory.outgoingMessagesBubbleImageWithColor(UIColor.jsq_messageBubbleGreenColor())
        
        // アバターの設定
        self.incomingAvatar = JSQMessagesAvatarImageFactory.avatarImageWithImage(UIImage(named: "watson.png")!, diameter: 64)
        self.outgoingAvatar = JSQMessagesAvatarImageFactory.avatarImageWithImage(UIImage(named: "you.png")!, diameter: 64)
        
        // メッセージデータの配列を初期化
        self.messages = []
        
        receiveAutoMessage()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: Override Method
    
    /// Sendボタンが押された時に呼ばれる
    override func didPressSendButton(button: UIButton!, withMessageText text: String!, senderId: String!, senderDisplayName: String!, date: NSDate!) {
        
        // 新しいメッセージデータを追加する
        let message = JSQMessage(senderId: senderId, displayName: senderDisplayName, text: text)
        self.messages?.append(message)
        
        // メッセジの送信処理を完了する(画面上にメッセージが表示される)
        self.finishReceivingMessageAnimated(true)
        
        // メッセージを受信
        self.receiveAutoMessage()
        
    }
    
    /// アイテムごとに参照するメッセージデータを返す
    override func collectionView(collectionView: JSQMessagesCollectionView!, messageDataForItemAtIndexPath indexPath: NSIndexPath!) -> JSQMessageData! {
        return self.messages?[indexPath.item]
    }
    
    /// アイテムごとのMessageBubble(背景)を返す
    override func collectionView(collectionView: JSQMessagesCollectionView!, messageBubbleImageDataForItemAtIndexPath indexPath: NSIndexPath!) -> JSQMessageBubbleImageDataSource! {
        let message = self.messages?[indexPath.item]
        if message?.senderId == self.senderId {
            return self.outgoingBubble
        }
        return self.incomingBubble
    }
    
    /// アイテムごとにアバター画像を返す
    override func collectionView(collectionView: JSQMessagesCollectionView!, avatarImageDataForItemAtIndexPath indexPath: NSIndexPath!) -> JSQMessageAvatarImageDataSource! {
        let message = self.messages?[indexPath.item]
        if message?.senderId == self.senderId {
            return self.outgoingAvatar
        }
        return self.incomingAvatar
    }
    
    /// アイテムの総数を返す
    override func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return (self.messages?.count)!
    }
    
    // MARK: Private Method
    
    /// 返信メッセージを受信する
    func receiveAutoMessage() {
        SVProgressHUD.show()
        if self.conversationId == "" {
            postDialog("")
        } else {
            let inputText = self.inputToolbar.contentView.textView.text
            self.inputToolbar.contentView.textView.text = ""
            postDialog(inputText)
        }
    }
    
    /// Watson Dialogと対話を行う
    /// - parameter input: 入力テキスト
    func postDialog(input: String) {
        // conversation_idとは複数クライアントから同じDialogにアクセスしても独立した対話になるように割り振られるID
        // conversation_idは初回のAPIアクセス時に返却され、２回目以降の対話ではconversation_idが必須となる
        let params = [
            "conversation_id": self.conversationId,
            "client_id": self.clientId,
            "input": input,
            ]
        Alamofire.request(.POST, "https://gateway.watsonplatform.net/dialog/api/v1/dialogs/\(self.DIALOG_ID)/conversation", parameters: params)
            .authenticate(user: self.DIALOG_USER, password: self.DIALOG_PASS)
            .responseJSON { response in
                if response.result.error == nil {
                    guard let object = response.result.value else {
                        return
                    }
                    let json = JSON(object)
                    print("\n--Debug postDialog json:")
                    print(json)
                    if self.conversationId == "" {
                        self.conversationId = json["conversation_id"].stringValue
                        self.clientId = json["client_id"].stringValue
                    }
                    let messageText = self.editResponse(json["response"].arrayValue)
                    if messageText.containsString(self.REPLACE_STRING) {
                        // 固定文字列が含まれていたらDialogの変数より絞り込み条件を取得しNLCからclassを取得し文字列置換する
                        self.getDialogVariables(messageText)
                    } else {
                        self.dispResponse(messageText)
                    }
                }
        }
    }
    
    /// Response配列のメッセージを編集する
    /// - parameter responseArray: WatsonのResponse要素（配列）
    /// - returns: 編集後の文字列
    func editResponse(responseArray: Array<SwiftyJSON.JSON>) -> String {
        var messageText: String = ""
        for text in responseArray {
            if messageText != "" {
                messageText += "\n"
            }
            messageText += text.string!
        }
        return messageText
    }
    
    /// Watson Dialogの変数（＝絞り込み条件）を取得する
    /// - parameter messageText: 表示文字列
    func getDialogVariables(messageText: String) {
        Alamofire.request(.GET, "https://gateway.watsonplatform.net/dialog/api/v1/dialogs/\(self.DIALOG_ID)/profile?client_id=\(self.clientId)")
            .authenticate(user: self.DIALOG_USER, password: self.DIALOG_PASS)
            .responseJSON { response in
                print("\n--Debug getDialogVariables response:")
                print(response.result.value)
                if response.result.error == nil {
                    guard let object = response.result.value else {
                        return
                    }
                    let json = JSON(object)
                    print("\n--Debug getDialogVariables json:")
                    print(json)
                    // Dialogの変数名と値を配列化
                    let variables = json["name_values"].arrayValue
                    var classifierId = ""
                    var filterText = ""
                    for varText in variables {
                        guard let varName = varText["name"].string else {
                            return
                        }
                        if varName == self.DIALOG_VAR_TITLE {
                            // 作品名指定の場合
                            classifierId = self.CLASSIFIER_ID_TITLE
                            if varText["value"].stringValue != "" {
                                filterText = varText["value"].stringValue
                                break
                            }
                        }
                        if varName == self.DIALOG_VAR_STARRING {
                            // 出演者名指定の場合
                            classifierId = self.CLASSIFIER_ID_STARRING
                            if varText["value"].stringValue != "" {
                                filterText = varText["value"].stringValue
                                break
                            }
                        }
                    }
                    self.getClassFromNLC(classifierId, messageText: messageText, filterText: filterText)
                }
        }
    }
    
    /// NLCのResponseを取得する
    /// - parameter classifierId: ClassifierID
    /// - parameter messageText: 表示文字列
    /// - parameter filterText: フィルタ文字列
    func getClassFromNLC(classifierId: String, messageText: String, filterText: String) {
        let params = [
            "text": filterText,
            ]
        Alamofire.request(.GET, "https://gateway.watsonplatform.net/natural-language-classifier/api/v1/classifiers/\(classifierId)/classify", parameters: params)
            .authenticate(user: self.NLC_USER, password: self.NLC_PASS)
            .responseJSON { response in
                print("\n--Debug getClassFromNLC response:")
                print(response.result.value)
                if response.result.error == nil {
                    guard let object = response.result.value else {
                        return
                    }
                    let json = JSON(object)
                    print("\n--Debug getClassFromNLC json:")
                    print(json)
                    let classJson = json["classes"].arrayValue
                    var dispText = ""
                    if classJson.count > 0 {
                        for i in 0...classJson.count - 1 {
                            // classes配列は確信度の降順に並んでいる（らしい）のでそのまま使う
                            if i > 2 {
                                // 3件超は長くなりすぎるので
                                break
                            }
                            if dispText != "" {
                                dispText += "または"
                            }
                            dispText += ("「" + classJson[i]["class_name"].stringValue + "」")
                        }
                    }
                    let s = messageText.stringByReplacingOccurrencesOfString(self.REPLACE_STRING, withString: dispText)
                    self.dispResponse(s)
                }
        }
    }
    
    /// Responseをチャットに表示する
    /// - parameter responseText: 表示文字列
    func dispResponse (responseText: String) {
        let message = JSQMessage(senderId: "user2", displayName: "underscore", text: responseText)
        self.messages?.append(message)
        self.finishReceivingMessageAnimated(true)
        SVProgressHUD.dismiss()
    }
    
}
