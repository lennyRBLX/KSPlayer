//
//  PlayerTransitionAnimator.swift
//  KSPlayer
//
//  Created by kintan on 2021/8/20.
//

#if canImport(UIKit)
import UIKit

/// RE: 0x1014F0F24 (_objc_opt_self(PlayerTransitionAnimator), 1.3.15)
/// AVKit-style zoom transition (0.3s, scale + translate, identity-transform reset).
class PlayerTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let isDismiss: Bool
    private let containerView: UIView
    private let animationView: UIView
    private let fromCenter: CGPoint
    /// RE: 0x1014F0FE4 (PlayerTransitionAnimator.init(containerView:animationView:isDismiss:), 1.3.15)
    init(containerView: UIView, animationView: UIView, isDismiss: Bool = false) {
        self.containerView = containerView
        self.animationView = animationView
        self.isDismiss = isDismiss
        fromCenter = containerView.superview?.convert(containerView.center, to: nil) ?? .zero
        super.init()
    }

    func transitionDuration(using _: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.3
    }

    /// RE: 0x1014F0508 (PlayerTransitionAnimator.animateTransition(using:), 1.3.15)
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let animationSuperView = animationView.superview
        let animationViewIndex = animationSuperView?.subviews.firstIndex(of: animationView) ?? 0
        let initSize = animationView.frame.size
        let animationFrameConstraints = animationView.frameConstraints
        guard let presentedView = transitionContext.view(forKey: isDismiss ? .from : .to) else {
            return
        }
        if isDismiss {
            containerView.layoutIfNeeded()
            presentedView.bounds = containerView.bounds
            presentedView.removeFromSuperview()
        } else {
            if let viewController = transitionContext.viewController(forKey: .to) {
                presentedView.frame = transitionContext.finalFrame(for: viewController)
            }
        }
        presentedView.layoutIfNeeded()
        transitionContext.containerView.addSubview(animationView)
        animationView.translatesAutoresizingMaskIntoConstraints = true
        guard let transform = transitionContext.viewController(forKey: .from)?.view.transform else {
            return
        }
        animationView.transform = CGAffineTransform(scaleX: initSize.width / animationView.frame.size.width, y: initSize.height / animationView.frame.size.height).concatenating(transform)
        let toCenter = transitionContext.containerView.center
        let fromCenter = transform == .identity ? fromCenter : fromCenter.reverse
        animationView.center = isDismiss ? toCenter : fromCenter
        UIView.animate(withDuration: transitionDuration(using: transitionContext), delay: 0, options: .curveEaseInOut) {
            // RE: 0x1014F0AB0 (animationBlock_impl, 1.3.15) — identity transform + setCenter.
            self.animationView.transform = .identity
            self.animationView.center = self.isDismiss ? fromCenter : toCenter
        } completion: { _ in
            // RE: 0x1014F0BB4 (completionBlock_impl, 1.3.15) — reinsert subview, reactivate constraints, completeTransition(true).
            animationSuperView?.insertSubview(self.animationView, at: animationViewIndex)
            if !animationFrameConstraints.isEmpty {
                self.animationView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate(animationFrameConstraints)
            }
            if !self.isDismiss {
                transitionContext.containerView.addSubview(presentedView)
            }
            transitionContext.completeTransition(true)
        }
    }
}
#endif
