//
//  CustomShareViewController.swift
//  OxChatShareExtension
//
//  Created by W on 2025/9/3.
//

import UIKit
import Social
import CoreServices

class CustomShareViewController: UIViewController {
    
    private let containerView = UIView()
    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let contentView = UIView()
    private let previewImageView = UIImageView()
    private let urlTextLabel = UILabel()
    private let shareButton = UIButton(type: .system)
    
    private var sharedData: SharedData?
    private var isProcessing = false
    
    struct SharedData {
        let type: String
        let content: String
        let image: UIImage?
        let filePath: String?
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSharedContent()
    }
    
    private func setupUI() {
        setupContainerView()
        setupHeaderView()
        setupContentView()
        setupButtons()
        setupConstraints()
    }
    
    private func setupContainerView() {
        containerView.backgroundColor = UIColor.systemBackground
        containerView.layer.cornerRadius = 12
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: -2)
        containerView.layer.shadowRadius = 8
        containerView.layer.shadowOpacity = 0.1
        
        view.addSubview(containerView)
    }
    
    private func setupHeaderView() {
        // Title
        titleLabel.text = "Share to XChat"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        titleLabel.textAlignment = .center
        titleLabel.textColor = UIColor.label
        
        // Close button
        closeButton.setTitle("✕", for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 20)
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        
        headerView.addSubview(titleLabel)
        headerView.addSubview(closeButton)
        containerView.addSubview(headerView)
    }
    
    private func setupContentView() {
        // Preview image
        previewImageView.contentMode = .scaleAspectFit
        previewImageView.clipsToBounds = true
        
        // Text view
        urlTextLabel.font = UIFont.systemFont(ofSize: 16)
        urlTextLabel.numberOfLines = 3
        
        contentView.addSubview(previewImageView)
        contentView.addSubview(urlTextLabel)
        containerView.addSubview(contentView)
    }
    
    private func setupButtons() {
        // Share button
        shareButton.setTitle("Share", for: .normal)
        shareButton.backgroundColor = UIColor.systemBlue
        shareButton.setTitleColor(.white, for: .normal)
        shareButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        shareButton.layer.cornerRadius = 8
        shareButton.addTarget(self, action: #selector(shareButtonTapped), for: .touchUpInside)
        
        containerView.addSubview(shareButton)
    }
    
    private func setupConstraints() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        urlTextLabel.translatesAutoresizingMaskIntoConstraints = false
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Container view
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Header view
            headerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50),
            
            // Title label
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            // Close button
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16),
            contentView.bottomAnchor.constraint(equalTo: shareButton.topAnchor, constant: -30),
            contentView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            contentView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            
            // Preview image
            previewImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            previewImageView.widthAnchor.constraint(equalToConstant: 32),
            previewImageView.heightAnchor.constraint(equalToConstant: 32),
            
            // Text view
            urlTextLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            urlTextLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            urlTextLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            urlTextLabel.leadingAnchor.constraint(equalTo: previewImageView.trailingAnchor, constant: 12),
            urlTextLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Share button
            shareButton.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            shareButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            shareButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            shareButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }
    
    @objc private func closeButtonTapped() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    @objc private func shareButtonTapped() {
        guard !isProcessing else { return }
        
        isProcessing = true
        shareButton.setTitle("Processing...", for: .normal)
        shareButton.isEnabled = false
        
        processAndShare()
    }
    
    private func loadSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem else {
            return
        }
        
        if let attachments = extensionItem.attachments {
            for itemProvider in attachments {
                let urlIdentifier = kUTTypeURL as String
                let imageIdentifier = kUTTypeImage as String
                let movieIdentifier = kUTTypeMovie as String
                
                if itemProvider.hasItemConformingToTypeIdentifier(urlIdentifier) {
                    itemProvider.loadItem(forTypeIdentifier: urlIdentifier, options: nil) { [weak self] (data, error) in
                        DispatchQueue.main.async {
                            if let url = data as? URL {
                                self?.sharedData = SharedData(
                                    type: "url",
                                    content: url.absoluteString,
                                    image: nil,
                                    filePath: nil
                                )
                                self?.updateUI()
                            }
                        }
                    }
                } else if itemProvider.hasItemConformingToTypeIdentifier(imageIdentifier) {
                    itemProvider.loadItem(forTypeIdentifier: imageIdentifier, options: nil) { [weak self] (data, error) in
                        DispatchQueue.main.async {
                            if let url = data as? URL, let image = UIImage(contentsOfFile: url.path) {
                                self?.sharedData = SharedData(
                                    type: "image",
                                    content: "",
                                    image: image,
                                    filePath: url.path
                                )
                                self?.updateUI()
                            }
                        }
                    }
                } else if itemProvider.hasItemConformingToTypeIdentifier(movieIdentifier) {
                    itemProvider.loadItem(forTypeIdentifier: movieIdentifier, options: nil) { [weak self] (data, error) in
                        DispatchQueue.main.async {
                            if let url = data as? URL {
                                self?.sharedData = SharedData(
                                    type: "video",
                                    content: "",
                                    image: nil,
                                    filePath: url.path
                                )
                                self?.updateUI()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func updateUI() {
        guard let data = sharedData else { return }
        
        switch data.type {
        case "url":
            urlTextLabel.text = data.content
            previewImageView.image = UIImage(systemName: "link")
        case "image":
            previewImageView.image = data.image
        case "video":
            previewImageView.image = UIImage(systemName: "video")
        default:
            break
        }
    }
    
    private func processAndShare() {
        guard let data = sharedData else {
            completeRequest()
            return
        }
        
        // Save data to App Group
        if data.type == "url" {
            AppGroupHelper.saveDataForGourp(data.content, forKey: AppGroupHelper.shareDataURLKey)
        } else if data.type == "image" || data.type == "video" {
            if let filePath = data.filePath {
                AppGroupHelper.saveDataForGourp(filePath, forKey: AppGroupHelper.shareDataFilePathKey)
            }
        }
        
        // Save additional text if provided
        if !(urlTextLabel.text ?? "").isEmpty {
            AppGroupHelper.saveDataForGourp(urlTextLabel.text, forKey: "shareText")
        }
        
        // Open main app
        openMainApp()
    }
    
    private func openMainApp() {
        guard let scheme = URL(string: AppGroupHelper.shareScheme) else {
            completeRequest()
            return
        }
        
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(scheme) { [weak self] success in
                    DispatchQueue.main.async {
                        self?.completeRequest()
                    }
                }
                return
            }
            responder = responder?.next
        }
        
        completeRequest()
    }
    
    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}

