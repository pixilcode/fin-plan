#!/usr/bin/env nu

const outdir = "fin-plan-output"

def main [...csv_files: path] {
  if ($csv_files | length) == 0 {
    print --stderr "error: need to provide paths"
    exit 1
  }

  if (open ...$csv_files | length) == 0 {
    print --stderr "error: no files found"
    exit 1
  }

  mkdir $outdir

  let data = (
    open ...$csv_files
    | select "Account Number" "Post Date" "Description" "Debit" "Credit"
    | rename account post_date description debit credit
    | update post_date { into datetime }
    | sort-by account post_date
    | insert category null
    | insert note null
    # TODO: run filters here
  )

  let income = (
    $data
    | where credit != ""
    | reject debit
    | rename --column {credit: amount}
    | process_accounts "income"
  )

  let expenses = (
    $data
    | where debit != ""
    | reject credit
    | rename --column {debit: amount}
    | process_accounts "expenses"
  )
}

def process_accounts [kind: string] {
    $in
    | group-by --to-table account
    | insert out { |account| $outdir | path join $"($kind).($account.account).csv" }
    | each { |account|
      # create the CSV file for writing
      # TODO: get rid of the `-f` flag when done testing
      $account.items | save -f $account.out
      soffice $account.out

      # read the results of the CSV file
      let updated_items = open $account.out

      # update the account
      $account
      | update items $updated_items
      | sort-by category # TODO: custom sort function
    }
}
