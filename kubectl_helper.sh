#!/bin/bash
# ==============================================================================
# K3s Kubectl Interactive Helper Script
# Helps users generate and execute kubectl commands dynamically based on live resources
# ==============================================================================

# Ensure standard K3s configuration is used
# Using explicit k3s kubectl allows this to work right away on RHEL 9 standard setups
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
CMD="k3s kubectl"

function main_menu {
    clear
    echo "========================================================="
    echo "       🚀 K3s Kubectl Interactive Helper Menu         "
    echo "========================================================="
    echo "This tool helps you explore and manage your cluster dynamically."
    echo ""
    echo "1. Explore Pods (Logs, Describe, Exec shell, Port-Forward)"
    echo "2. Explore Nodes (Describe, Resource Usage, Taint)"
    echo "3. Explore Deployments (Scale, Edit, Rollout status)"
    echo "4. Explore Services (Describe, Endpoints)"
    echo "5. Cluster Info & Current Context"
    echo "0. Exit"
    echo "---------------------------------------------------------"
    read -p "Select an option: " OPTION

    case $OPTION in
        1) menu_pods ;;
        2) menu_nodes ;;
        3) menu_deployments ;;
        4) menu_services ;;
        5) show_cluster_info ;;
        0) exit 0 ;;
        *) echo "Invalid option"; sleep 1; main_menu ;;
    esac
}

function select_namespace {
    echo "Fetching active namespaces..."
    # Read the output ignoring the header line
    # Array mapping prevents index issues
    mapfile -t NAMESPACES < <($CMD get namespaces -o custom-columns=":metadata.name" --no-headers)
    
    echo "Available Namespaces:"
    echo "0. [All Namespaces]"
    for i in "${!NAMESPACES[@]}"; do
        echo "$((i+1)). ${NAMESPACES[$i]}"
    done
    
    read -p "Select Namespace number (default: 0): " NS_OPT
    if [[ -z "$NS_OPT" || "$NS_OPT" == "0" ]]; then
        SELECTED_NS="--all-namespaces"
        NS_FLAG="-A"
        NS_NAME="All Namespaces"
    else
        # Match array index which is OPT-1
        IDX=$((NS_OPT-1))
        NS_NAME="${NAMESPACES[$IDX]}"
        if [[ -z "$NS_NAME" ]]; then
            echo "Invalid selection, defaulting to all namespaces."
            SELECTED_NS="--all-namespaces"
            NS_FLAG="-A"
        else
            SELECTED_NS="-n $NS_NAME"
            NS_FLAG="-n $NS_NAME"
        fi
    fi
}

function menu_pods {
    clear
    echo "--- Manage Pods ---"
    select_namespace
    
    echo "Fetching pods in $NS_NAME..."
    mapfile -t PODS < <($CMD get pods $SELECTED_NS -o custom-columns=":metadata.name" --no-headers)
    
    if [ ${#PODS[@]} -eq 0 ]; then
        echo "No pods found in $NS_NAME."
        read -p "Press Enter to return to main menu..."
        main_menu
        return
    fi
    
    echo "Available Pods:"
    for i in "${!PODS[@]}"; do
        echo "$((i+1)). ${PODS[$i]}"
    done
    read -p "Select Pod number: " POD_OPT
    if [[ -z "$POD_OPT" || ! "$POD_OPT" =~ ^[0-9]+$ || "$POD_OPT" -lt 1 || "$POD_OPT" -gt ${#PODS[@]} ]]; then
        echo "Invalid pod selection."
        sleep 1; main_menu; return
    fi
    
    SELECTED_POD="${PODS[$((POD_OPT-1))]}"
    
    # If we searched all namespaces, we need to extract the actual namespace of the pod to perform actions
    if [ "$NS_NAME" == "All Namespaces" ]; then
        pod_ns_raw=$($CMD get pod $SELECTED_POD -A -o custom-columns=":metadata.namespace" --no-headers 2>/dev/null | head -n 1)
        ACTION_NS="-n $pod_ns_raw"
    else
        ACTION_NS="$SELECTED_NS"
    fi
    
    echo ""
    echo "Selected Pod: $SELECTED_POD"
    echo "Choose action:"
    echo "1. Get Logs (Top 100 lines)"
    echo "2. Follow Logs Live (-f)"
    echo "3. Describe Pod"
    echo "4. Open Shell (sh/bash) inside pod"
    echo "5. Delete Pod (Forces Recreation if managed by Deployment)"
    echo "0. Back to Main Menu"
    read -p "Action: " ACTION
    
    echo "---------------------------------------------------------"
    case $ACTION in
        1) 
            echo "> Running: kubectl logs $SELECTED_POD $ACTION_NS --tail=100"
            $CMD logs $SELECTED_POD $ACTION_NS --tail=100
            ;;
        2) 
            echo "> Running: kubectl logs -f $SELECTED_POD $ACTION_NS"
            echo "Press Ctrl+C to stop following logs."
            $CMD logs -f $SELECTED_POD $ACTION_NS
            ;;
        3) 
            echo "> Running: kubectl describe pod $SELECTED_POD $ACTION_NS"
            $CMD describe pod $SELECTED_POD $ACTION_NS | less -r
            ;;
        4) 
            echo "> Running: kubectl exec -it $SELECTED_POD $ACTION_NS -- /bin/sh"
            $CMD exec -it $SELECTED_POD $ACTION_NS -- /bin/sh || $CMD exec -it $SELECTED_POD $ACTION_NS -- /bin/bash
            ;;
        5) 
            echo "> Running: kubectl delete pod $SELECTED_POD $ACTION_NS"
            $CMD delete pod $SELECTED_POD $ACTION_NS
            ;;
        0) main_menu; return ;;
        *) echo "Invalid action." ;;
    esac
    
    echo "---------------------------------------------------------"
    read -p "Press Enter to return to main menu..."
    main_menu
}

function menu_nodes {
    clear
    echo "--- Manage Nodes ---"
    mapfile -t NODES < <($CMD get nodes -o custom-columns=":metadata.name" --no-headers)
    
    for i in "${!NODES[@]}"; do
        echo "$((i+1)). ${NODES[$i]}"
    done
    read -p "Select Node number: " NODE_OPT
    if [[ -z "$NODE_OPT" || ! "$NODE_OPT" =~ ^[0-9]+$ || "$NODE_OPT" -lt 1 || "$NODE_OPT" -gt ${#NODES[@]} ]]; then
        echo "Invalid node selection."
        sleep 1; main_menu; return
    fi
    
    SELECTED_NODE="${NODES[$((NODE_OPT-1))]}"
    
    echo ""
    echo "Selected Node: $SELECTED_NODE"
    echo "Choose action:"
    echo "1. Describe Node (Detailed stats, limits, condition)"
    echo "2. Check Resource Utilization (kubectl top node)"
    echo "3. Drain Node (Evict all pods)"
    echo "4. Cordon Node (Disable scheduling)"
    echo "5. Uncordon Node"
    echo "0. Back to Main Menu"
    read -p "Action: " ACTION
    
    echo "---------------------------------------------------------"
    case $ACTION in
        1) 
            echo "> Running: kubectl describe node $SELECTED_NODE"
            $CMD describe node $SELECTED_NODE | less -r
            ;;
        2) 
            echo "> Running: kubectl top node $SELECTED_NODE"
            $CMD top node $SELECTED_NODE
            ;;
        3)
            echo "> Running: kubectl drain $SELECTED_NODE --ignore-daemonsets --delete-emptydir-data"
            read -p "Are you sure? (y/n): " confirm
            if [[ "$confirm" == "y" ]]; then
                $CMD drain $SELECTED_NODE --ignore-daemonsets --delete-emptydir-data
            fi
            ;;
        4)
            echo "> Running: kubectl cordon $SELECTED_NODE"
            $CMD cordon $SELECTED_NODE
            ;;
        5)
            echo "> Running: kubectl uncordon $SELECTED_NODE"
            $CMD uncordon $SELECTED_NODE
            ;;
        0) main_menu; return ;;
        *) echo "Invalid action." ;;
    esac
    
    echo "---------------------------------------------------------"
    read -p "Press Enter to return to main menu..."
    main_menu
}


function menu_deployments {
    clear
    echo "--- Manage Deployments ---"
    select_namespace
    
    mapfile -t DEPLOYS < <($CMD get deployments $SELECTED_NS -o custom-columns=":metadata.name" --no-headers)
    
    if [ ${#DEPLOYS[@]} -eq 0 ]; then
        echo "No deployments found in $NS_NAME."
        read -p "Press Enter to return to main menu..."
        main_menu
        return
    fi
    
    for i in "${!DEPLOYS[@]}"; do
        echo "$((i+1)). ${DEPLOYS[$i]}"
    done
    read -p "Select Deployment number: " DEP_OPT
    if [[ -z "$DEP_OPT" || ! "$DEP_OPT" =~ ^[0-9]+$ || "$DEP_OPT" -lt 1 || "$DEP_OPT" -gt ${#DEPLOYS[@]} ]]; then
        echo "Invalid selection."
        sleep 1; main_menu; return
    fi
    
    SELECTED_DEP="${DEPLOYS[$((DEP_OPT-1))]}"
    
    if [ "$NS_NAME" == "All Namespaces" ]; then
        dep_ns_raw=$($CMD get deployment $SELECTED_DEP -A -o custom-columns=":metadata.namespace" --no-headers 2>/dev/null | head -n 1)
        ACTION_NS="-n $dep_ns_raw"
    else
        ACTION_NS="$SELECTED_NS"
    fi
    
    echo ""
    echo "Selected Deployment: $SELECTED_DEP"
    echo "Choose action:"
    echo "1. Scale Replicas"
    echo "2. Restart Workload (Rollout Restart)"
    echo "3. Describe Deployment"
    echo "4. Edit Deployment (Opens in default standard editor like vi)"
    echo "0. Back to Main Menu"
    read -p "Action: " ACTION
    
    echo "---------------------------------------------------------"
    case $ACTION in
        1) 
            read -p "Enter new number of replicas: " REPLICAS
            echo "> Running: kubectl scale deployment $SELECTED_DEP $ACTION_NS --replicas=$REPLICAS"
            $CMD scale deployment $SELECTED_DEP $ACTION_NS --replicas=$REPLICAS
            ;;
        2) 
            echo "> Running: kubectl rollout restart deployment $SELECTED_DEP $ACTION_NS"
            $CMD rollout restart deployment $SELECTED_DEP $ACTION_NS
            ;;
        3) 
            echo "> Running: kubectl describe deployment $SELECTED_DEP $ACTION_NS"
            $CMD describe deployment $SELECTED_DEP $ACTION_NS | less -r
            ;;
        4) 
            echo "> Running: kubectl edit deployment $SELECTED_DEP $ACTION_NS"
            $CMD edit deployment $SELECTED_DEP $ACTION_NS
            ;;
        0) main_menu; return ;;
        *) echo "Invalid action." ;;
    esac
    
    echo "---------------------------------------------------------"
    read -p "Press Enter to return to main menu..."
    main_menu
}


function menu_services {
    clear
    echo "--- Manage Services ---"
    select_namespace
    
    mapfile -t SVCS < <($CMD get svc $SELECTED_NS -o custom-columns=":metadata.name" --no-headers)
    
    if [ ${#SVCS[@]} -eq 0 ]; then
        echo "No services found in $NS_NAME."
        read -p "Press Enter to return to main menu..."
        main_menu
        return
    fi
    
    for i in "${!SVCS[@]}"; do
        echo "$((i+1)). ${SVCS[$i]}"
    done
    read -p "Select Service number: " SVC_OPT
    if [[ -z "$SVC_OPT" || ! "$SVC_OPT" =~ ^[0-9]+$ || "$SVC_OPT" -lt 1 || "$SVC_OPT" -gt ${#SVCS[@]} ]]; then
        echo "Invalid selection."
        sleep 1; main_menu; return
    fi
    
    SELECTED_SVC="${SVCS[$((SVC_OPT-1))]}"
    
    if [ "$NS_NAME" == "All Namespaces" ]; then
        svc_ns_raw=$($CMD get svc $SELECTED_SVC -A -o custom-columns=":metadata.namespace" --no-headers 2>/dev/null | head -n 1)
        ACTION_NS="-n $svc_ns_raw"
    else
        ACTION_NS="$SELECTED_NS"
    fi
    
    echo ""
    echo "Selected Service: $SELECTED_SVC"
    echo "Choose action:"
    echo "1. Describe Service (IP, Ports, TargetPorts)"
    echo "2. Get Underlying Endpoints"
    echo "0. Back to Main Menu"
    read -p "Action: " ACTION
    
    echo "---------------------------------------------------------"
    case $ACTION in
        1) 
            echo "> Running: kubectl describe svc $SELECTED_SVC $ACTION_NS"
            $CMD describe svc $SELECTED_SVC $ACTION_NS
            ;;
        2) 
            echo "> Running: kubectl get endpoints $SELECTED_SVC $ACTION_NS"
            $CMD get endpoints $SELECTED_SVC $ACTION_NS
            ;;
        0) main_menu; return ;;
        *) echo "Invalid action." ;;
    esac
    
    echo "---------------------------------------------------------"
    read -p "Press Enter to return to main menu..."
    main_menu
}


function show_cluster_info {
    clear
    echo "--- Cluster Information ---"
    echo "> kubectl cluster-info"
    $CMD cluster-info
    echo ""
    echo "> kubectl get componentstatuses"
    $CMD get componentstatuses 2>/dev/null || echo "Component status API unavailable"
    echo ""
    echo "> Server Version:"
    $CMD version --short 2>/dev/null || $CMD version
    echo "---------------------------------------------------------"
    read -p "Press Enter to return to main menu..."
    main_menu
}

# Start script
main_menu
