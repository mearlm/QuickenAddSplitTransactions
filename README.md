Readme Version: __GIT_VERSION__

# Quicken Add Split Transactions

An AppleScript tool designed to automate and streamline adding split transactions to Quicken accounts.
NB: This file uses keyboard automation and will make your computer inaccessible while procewssing an input file;
Attempts to change window focus or type input may corrupt the data entry.  Wait for the Finished dialog to appear.
Also be aware that the keyboard automation, whiie significantly faster than I can retype the transaction data,
is quite slow (~1.3 seconds per new/split transaction entry).

## Version History
* **Version 3.0** (Latest) - Current stable release with final revisions.
* **Version 2.0** - Intermediate feature updates and code refinements.
* **Version 1.0** - Initial release.

## How to Use
1. I use an Excel workbook to generate the command file.  I may add that tool here when it is more stable,
   as it utilized a custom built macro to construct this output.  This tool exports the CSV command file.

   COMMAND FILE SYNTAX
   The command file can execute any of 3 commands:
	  NewTransaction - add a new Quicken transaction.  Arguments:
	     Date:  the transaction date (I use: mm/dd/yy form; other formats untested)
		 Payee: who sent or received these funds.
         Amount: the transaction total amount (i.e. sum of splits)
		
	     e.g., NewTransaction, "07/30/26", "Some Payee", "1,044.69"

      Split - enter a transaction split under this transaction, Arguments:
         Category:  the category you want the transaction split classified under
            (typically these pre-exist in Quicken categories list; new category names are untested)
         [Transfer Account Name: (optional) name of account to transfer the split value into]
	        Note that transfer split amounts *are* counted in the Total (new) transaction Amount,
            although they do not impact the target account's balance (since the value is transferred elsewhere)
	     Amount:  the split transaction amount; the value may be positive or negative, as appropriate

         e.g., Split, "My Category Name", "707.20"
               Split, "My Transfer Category Name", "Sales Tax Collected", "75.53"

      SaveTransaction - the command to close the split editor and prepare for the next new transaction entry

	     e.g. SaveTransaction

2. Open Quicken and select the account where the transactions should be imported as the active account.
      For safety, I use an empty "Upload" account for this purpose.  Once the transaction inport has been verified,
      I then use the "Move Transaction" feature in Quicken to shift the imported transctions to their final
      destination account.  If there are errors, the imported transaction set can be easily deleted,
      the command file updated, and the import redone.

2. Run the script using the macOS Script Editor or your preferred script launcher, or as a binary appllcation (my preference).
      You will likely need to tweek the Privacy & Security settings for the script to execute properly:
         Accessibility: enabled
         Automation: enabled

         I find after recompiling it is best to toggle these settings off and back on, or, if errors persist,
         removing and reinserting the applicaiton control entirely.  YMMV
