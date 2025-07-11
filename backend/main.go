package main

import (
	"context"
	"crypto/ecdsa"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"os"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/gorilla/mux"
	"github.com/joho/godotenv"
)

type MintRequest struct {
	Sales   float64 `json:"sales"`
	Company string  `json:"company"`
}

type MintResponse struct {
	Success      bool   `json:"success"`
	Message      string `json:"message"`
	TxHash       string `json:"txHash,omitempty"`
	BlockNumber  uint64 `json:"blockNumber,omitempty"`
	AmountMinted string `json:"amountMinted,omitempty"`
}

var (
	client       *ethclient.Client
	privateKey   *ecdsa.PrivateKey
	fromAddress  common.Address
	contract     *Token
	contractAddr common.Address
)

func main() {
	err := godotenv.Load()
	if err != nil {
		log.Println("Warning: .env file not found - using environment variables")
	}

	if err := initEthereum(); err != nil {
		log.Fatalf("Failed to initialize Ethereum client: %v", err)
	}
	defer client.Close()

	r := mux.NewRouter()
	r.HandleFunc("/mint", mintTokensHandler).Methods("POST")

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Server running on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, r))
}

func initEthereum() error {
	var err error

	client, err = ethclient.Dial(os.Getenv("ETH_NODE_URL"))
	if err != nil {
		return fmt.Errorf("failed to connect to Ethereum client: %v", err)
	}

	privateKeyHex := os.Getenv("PRIVATE_KEY")
	if privateKeyHex == "" {
		return fmt.Errorf("PRIVATE_KEY environment variable is not set")
	}

	privateKey, err = crypto.HexToECDSA(privateKeyHex)
	if err != nil {
		return fmt.Errorf("invalid private key: %v", err)
	}

	publicKey := privateKey.Public()
	publicKeyECDSA, ok := publicKey.(*ecdsa.PublicKey)
	if !ok {
		return fmt.Errorf("error casting public key to ECDSA")
	}

	fromAddress = crypto.PubkeyToAddress(*publicKeyECDSA)

	contractAddr = common.HexToAddress(os.Getenv("CONTRACT_ADDRESS"))
	if contractAddr == (common.Address{}) {
		return fmt.Errorf("CONTRACT_ADDRESS environment variable is not set")
	}

	contract, err = NewToken(contractAddr, client)
	if err != nil {
		return fmt.Errorf("failed to create contract instance: %v", err)
	}

	return nil
}

func mintTokensHandler(w http.ResponseWriter, r *http.Request) {
	var req MintRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request payload")
		return
	}

	if req.Sales <= 0 {
		respondWithError(w, http.StatusBadRequest, "Sales amount must be positive")
		return
	}

	if !common.IsHexAddress(req.Company) {
		respondWithError(w, http.StatusBadRequest, "Invalid Ethereum address")
		return
	}

	amount := big.NewInt(int64(req.Sales))
	decimals := big.NewInt(0).Exp(big.NewInt(10), big.NewInt(18), nil)
	amount.Mul(amount, decimals)

	auth, err := prepareTransaction()
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to prepare transaction: %v", err))
		return
	}

	targetAddress := common.HexToAddress(req.Company)
	tx, err := contract.MintSecure(auth, targetAddress, amount)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to mint tokens: %v", err))
		return
	}

	receipt, err := waitForTransaction(tx.Hash())
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, fmt.Sprintf("Error waiting for transaction: %v", err))
		return
	}

	if receipt.Status == types.ReceiptStatusFailed {
		respondWithError(w, http.StatusInternalServerError, "Transaction failed")
		return
	}

	respondWithJSON(w, http.StatusOK, MintResponse{
		Success:      true,
		Message:      "Tokens minted successfully",
		TxHash:       tx.Hash().Hex(),
		BlockNumber:  receipt.BlockNumber.Uint64(),
		AmountMinted: amount.String(),
	})
}

func prepareTransaction() (*bind.TransactOpts, error) {
	nonce, err := client.PendingNonceAt(context.Background(), fromAddress)
	if err != nil {
		return nil, fmt.Errorf("failed to get nonce: %v", err)
	}

	gasPrice, err := client.SuggestGasPrice(context.Background())
	if err != nil {
		return nil, fmt.Errorf("failed to get gas price: %v", err)
	}

	chainID, err := client.NetworkID(context.Background())
	if err != nil {
		return nil, fmt.Errorf("failed to get chain ID: %v", err)
	}

	auth, err := bind.NewKeyedTransactorWithChainID(privateKey, chainID)
	if err != nil {
		return nil, fmt.Errorf("failed to create transactor: %v", err)
	}

	auth.Nonce = big.NewInt(int64(nonce))
	auth.Value = big.NewInt(0)
	auth.GasLimit = uint64(300000)
	auth.GasPrice = gasPrice

	return auth, nil
}

func waitForTransaction(txHash common.Hash) (*types.Receipt, error) {
	ctx := context.Background()
	timeout := time.After(5 * time.Minute)
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-timeout:
			return nil, fmt.Errorf("timeout waiting for transaction")
		case <-ticker.C:
			receipt, err := client.TransactionReceipt(ctx, txHash)
			if err != nil {
				if err.Error() == "not found" {
					continue
				}
				return nil, err
			}
			return receipt, nil
		}
	}
}

func respondWithError(w http.ResponseWriter, code int, message string) {
	respondWithJSON(w, code, MintResponse{Success: false, Message: message})
}

func respondWithJSON(w http.ResponseWriter, code int, payload any) {
	response, _ := json.Marshal(payload)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	w.Write(response)
}
