defmodule Indexer.Transform.Celo.TransactionTokenTransfers do
  @moduledoc """
  Helper functions for generating ERC20 token transfers from native Celo coin
  transfers.

  CELO has a feature referred to as "token duality", where the native chain
  asset (CELO) can be used as both a native chain currency and as an ERC-20
  token. Unfortunately native chain asset transfers do not emit ERC-20 transfer
  events, which requires the artificial creation of entries in the
  `token_transfers` table.
  """
  require Logger

  alias Explorer.Chain.Cache.CeloCoreContracts

  @token_type "ERC-20"
  @transaction_buffer_size 20_000

  @doc """
  In order to avoid conflicts with real token transfers, for native token
  transfers we put a negative `log_index`.

  Each transaction within the block is assigned a so-called _buffer_ of
  #{@transaction_buffer_size} entries. Thus, according to the formula,
  transactions with indices 0, 1, 2 would have log indices -20000, -40000,
  -60000.

  The spare intervals between the log indices (0..-19_999, -20_001..-39_999,
  -40_001..59_999) are reserved for native token transfers fetched from
  internal transactions.
  """
  def parse_transactions(transactions) do
    celo_token_address = CeloCoreContracts.get_celo_token_address()

    token_transfers =
      transactions
      |> Enum.filter(fn tx -> tx.value > 0 end)
      |> Enum.map(fn tx ->
        to_address_hash = Map.get(tx, :to_address_hash) || Map.get(tx, :created_contract_address_hash)
        log_index = -1 * (tx.index + 1) * @transaction_buffer_size

        %{
          amount: Decimal.new(tx.value),
          block_hash: tx.block_hash,
          block_number: tx.block_number,
          from_address_hash: tx.from_address_hash,
          log_index: log_index,
          to_address_hash: to_address_hash,
          token_contract_address_hash: celo_token_address,
          token_ids: nil,
          token_type: @token_type,
          transaction_hash: tx.hash
        }
      end)

    Logger.debug("Found #{length(token_transfers)} Celo token transfers.")

    %{
      token_transfers: token_transfers,
      tokens: to_tokens(token_transfers)
    }
  end

  def parse_internal_transactions(transactions, block_number_to_block_hash) do
    celo_token_address = CeloCoreContracts.get_celo_token_address()

    token_transfers =
      transactions
      |> Enum.filter(fn tx ->
        tx.value > 0 &&
          tx.index > 0 &&
          not Map.has_key?(tx, :error) &&
          (not Map.has_key?(tx, :call_type) || tx.call_type != "delegatecall")
      end)
      |> Enum.map(fn tx ->
        to_address_hash = Map.get(tx, :to_address_hash) || Map.get(tx, :created_contract_address_hash)
        log_index = -1 * (tx.transaction_index * @transaction_buffer_size + tx.index)

        %{
          amount: Decimal.new(tx.value),
          block_hash: block_number_to_block_hash[tx.block_number],
          block_number: tx.block_number,
          from_address_hash: tx.from_address_hash,
          log_index: log_index,
          to_address_hash: to_address_hash,
          token_contract_address_hash: celo_token_address,
          token_ids: nil,
          token_type: @token_type,
          transaction_hash: tx.transaction_hash
        }
      end)

    Logger.debug("Found #{length(token_transfers)} Celo token transfers from internal transactions.")

    %{
      token_transfers: token_transfers,
      tokens: to_tokens(token_transfers)
    }
  end

  defp to_tokens([]), do: []

  defp to_tokens(_token_transfers) do
    [
      %{
        contract_address_hash: CeloCoreContracts.get_celo_token_address(),
        type: @token_type
      }
    ]
  end
end
