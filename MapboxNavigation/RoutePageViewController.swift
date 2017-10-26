import UIKit
import MapboxDirections
import MapboxCoreNavigation

protocol RoutePageViewControllerDelegate: class {
    var currentLeg: RouteLeg { get }
    var currentStep: RouteStep { get }
    var upComingStep: RouteStep? { get }
    func stepBefore(_ step: RouteStep) -> RouteStep?
    func stepAfter(_ step: RouteStep) -> RouteStep?
    // `didSwipe` is only true when this function is invoked via the user swiping
    func routePageViewController(_ controller: RoutePageViewController, willTransitionTo maneuverViewController: RouteManeuverViewController, didSwipe: Bool)
}

class RoutePageViewController: UIPageViewController {
    
    weak var maneuverDelegate: RoutePageViewControllerDelegate!
    var currentManeuverPage: RouteManeuverViewController!
    
    var maneuverContainerView: ManeuverContainerView { return view.superview! as! ManeuverContainerView }

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource = self
        delegate = self
        view.clipsToBounds = false
        // Disable clipsToBounds on the hidden UIQueuingScrollView to render the shadows properly
        view.subviews.first?.clipsToBounds = false
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(true)
        updateManeuverViewForStep()
    }
    
    func updateManeuverViewForStep() {
        let upcomingStep = maneuverDelegate.upComingStep
        let leg = maneuverDelegate.currentLeg
        let controller = routeManeuverViewController(with: upcomingStep, currentStep: maneuverDelegate.currentStep, leg: leg)!
        setViewControllers([controller], direction: .forward, animated: false, completion: nil)
        currentManeuverPage = controller
        maneuverDelegate.routePageViewController(self, willTransitionTo: controller, didSwipe: false)
    }
    
    func routeManeuverViewController(with upcomingStep: RouteStep?, currentStep: RouteStep?, leg: RouteLeg?) -> RouteManeuverViewController? {
        guard upcomingStep != nil else {
            return nil
        }
        
        let storyboard = UIStoryboard(name: "Navigation", bundle: .mapboxNavigation)
        let controller = storyboard.instantiateViewController(withIdentifier: "RouteManeuverViewController") as! RouteManeuverViewController
        controller.upcomingStep = upcomingStep
        controller.currentStep = currentStep
        controller.leg = leg
        return controller
    }
}

extension RoutePageViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        let controller = viewController as! RouteManeuverViewController
        let stepAfter = maneuverDelegate.stepAfter(controller.upcomingStep!)
        let leg = maneuverDelegate.currentLeg
        return routeManeuverViewController(with: stepAfter, currentStep: controller.upcomingStep, leg: leg)
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        let controller = viewController as! RouteManeuverViewController
        let stepBefore = maneuverDelegate.stepBefore(controller.upcomingStep!)
        let leg = maneuverDelegate.currentLeg
        return routeManeuverViewController(with: stepBefore, currentStep: controller.upcomingStep, leg: leg)
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        let controller = pendingViewControllers.first! as! RouteManeuverViewController
        maneuverDelegate.routePageViewController(self, willTransitionTo: controller, didSwipe: true)
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard let controller = pageViewController.viewControllers?.last as? RouteManeuverViewController else { return }
        
        if completed {
            currentManeuverPage = controller
        }
    }
}
