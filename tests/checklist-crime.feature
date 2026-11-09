# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_robberies — Crime

  @kora_robberies @checklist @checklist:kora_robberies:creator-open @cat:crime @needs:admin
  Scenario: Open robbery creator (staff)
    """
    Checklist test: Run /robberyCreator as an admin (ace 'command'). Non-admins should be refused. README still says /houseCreator.
    """
    Given my job is "unemployed"
    When I run the command "/robberyCreator"
    Then the "qbrobberies:creator" app should be open
    And I confirm: a non-admin player is refused and the creator does not open

  @kora_robberies @checklist @checklist:kora_robberies:creator-item-lists @cat:crime @needs:admin
  Scenario: Create and edit item lists
    """
    Checklist test: Creator > Item lists: make a list, search/add items, edit amounts, remove items, delete the list.
    """
    When I manually: open the robbery creator with the staff creator command and go to Item lists
    Then the "qbrobberies:creator" app should be open
    When I manually: create a new item list
    And I manually: search for an item and add it to the list
    And I manually: edit the amount of an item in the list
    And I manually: remove an item from the list
    And I manually: delete the list
    Then I confirm: each change is saved and shown correctly in the Item lists page

  @kora_robberies @checklist @checklist:kora_robberies:creator-shell-props @cat:crime @needs:admin
  Scenario: Set up shell: exit and props
    """
    Checklist test: Creator > Shells: enter a shell, set the exit by aiming, place props/box targets with an item list, edit search settings, delete.
    """
    When I manually: open the robbery creator with the staff creator command and go to Shells
    Then the "qbrobberies:creator" app should be open
    When I manually: enter a shell and aim where the exit goes to set the exit
    And I manually: place a prop with an item list
    And I manually: place a box target (leave the prop model empty) with an item list
    And I manually: open Search settings on a placed prop and change the values
    Then a menu titled "Search settings" opens
    When I manually: delete a placed prop
    Then I confirm: the exit, props and box targets are placed where I aimed and the edits and deletion are saved

  @kora_robberies @checklist @checklist:kora_robberies:creator-break-item @cat:crime @needs:admin
  Scenario: Per-shell break-in item
    """
    Checklist test: Creator > Shells > Break-in item: change item required, then verify houses using that shell need it.
    """
    When I manually: open the robbery creator with the staff creator command, go to Shells and open Break-in item
    Then the "qbrobberies:creator" app should be open
    When I manually: change the required break-in item for a shell
    And I manually: go to a house that uses that shell and try to break in without the new item
    Then I confirm: the break-in is refused without the new item
    When I manually: get the new item and try to break in again
    Then I confirm: the break-in works with the new item

  @kora_robberies @checklist @checklist:kora_robberies:creator-houses @cat:crime @needs:admin
  Scenario: Place and configure houses
    """
    Checklist test: Creator > Houses: pick shell, aim at doors to place houses, rename, set min police, cooldown, security flag and hours.
    """
    When I manually: open the robbery creator with the staff creator command and go to Houses
    Then the "qbrobberies:creator" app should be open
    When I manually: pick a shell and aim at doors to place houses
    And I manually: rename a house
    And I manually: set its minimum police, cooldown, security flag and hours
    Then I confirm: the houses are placed at the doors I aimed at and the name and settings are saved

  @kora_robberies @checklist @checklist:kora_robberies:creator-stores @cat:crime @needs:admin
  Scenario: Create stores with registers/safes
    """
    Checklist test: Creator > Stores: create store, set name/min police, place registers (sticky note chance) and safes by aiming.
    """
    When I manually: open the robbery creator with the staff creator command and go to Stores
    Then the "qbrobberies:creator" app should be open
    When I manually: create a store and set its name and minimum police
    And I manually: place a register by aiming and set its sticky note chance
    And I manually: place a safe by aiming
    Then I confirm: the store, register and safe are saved and appear in the Stores page

  @kora_robberies @checklist @checklist:kora_robberies:house-break-in @cat:crime
  Scenario: Break in to an available house
    """
    Checklist test: Target a house door, 'Break in' needs lockpick item and min police; 8s progress, item consumed, you enter the shell.
    """
    Given I have 1 "lockpick"
    When I manually: go to a house door and select the Break in target
    Then a progress bar should run
    And I confirm: the progress bar lasts about 8 seconds
    And I should have no "lockpick"
    And I confirm: I enter the house shell
    And I confirm: Break in is refused when there are fewer police online than the house minimum (only applies when the house has a minimum police above 0)

  @kora_robberies @checklist @checklist:kora_robberies:house-security @cat:crime
  Scenario: Security-system house needs extra item
    """
    Checklist test: On a security house, break-in also needs electronickit and fires qbrobberies:houseAlert (dispatch hook).
    """
    Given I have 1 "lockpick"
    When I manually: go to a house with the security system on and try to break in with only the lockpick
    Then I confirm: the break-in is refused without the electronickit
    When I manually: get an electronickit and a lockpick, then try to break in again
    Then I confirm: the break-in works
    And I confirm: the dispatch hook receives the house alert with the house, label and coords

  @kora_robberies @checklist @checklist:kora_robberies:house-search-props @cat:crime
  Scenario: Search props inside the house
    """
    Checklist test: Inside a shell target a prop/box and 'Search': progress bar, random item from its list; one searcher per prop, once per robbery.
    """
    When I manually: go inside a robbed house shell and select Search on a prop or box target
    Then a progress bar labelled "Searching..." should run
    And I confirm: I receive one random item from the prop's list and a notification that I found it
    When I manually: ask a second player to try to search the same prop while I am searching it
    Then I confirm: the other player cannot search that prop at the same time
    When I manually: try to search the same prop again
    Then I confirm: it cannot be searched a second time in the same robbery

  @kora_robberies @checklist @checklist:kora_robberies:house-states @cat:crime @manual
  Scenario: House Available/Open/Cooldown states
    """
    Checklist test: After a break-in the door shows 'Enter' for all players (15 min), then 'Recently robbed' during cooldown, then 'Break in' again.
    """
    When I manually: break in to an available house
    And I manually: ask a second player to look at the same house door
    Then I confirm: the door target shows Enter for both of us
    When I manually: wait for the 15 minute open time to end
    Then I confirm: the door target shows Recently robbed during the cooldown
    When I manually: wait for the house cooldown to end
    Then I confirm: the door target shows Break in again

  @kora_robberies @checklist @checklist:kora_robberies:house-leave @cat:crime
  Scenario: Leave house and forced eviction
    """
    Checklist test: Use the 'Leave' target at the shell exit; when the open timer ends everyone inside is sent out with a notice.
    """
    When I manually: break in to a house and walk to the shell exit
    And I manually: select the Leave target at the exit
    Then I confirm: I am taken outside the house
    When I manually: enter the house again and wait inside until the open timer ends
    Then I should see a notification containing "The robbery is over. You have been sent out."
    And I confirm: everyone inside the house is sent out

  @kora_robberies @checklist @checklist:kora_robberies:house-restrictions @cat:crime
  Scenario: Police/hours/item gating
    """
    Checklist test: Try break-in with too few police, outside allowed hours, or without the item: should show an error and not enter.
    """
    Given I have no "lockpick"
    When I manually: try to break in to a house with fewer police online than its minimum
    Then I confirm: an error is shown and I do not enter
    When I manually: try to break in outside the house's allowed hours
    Then I confirm: an error is shown and I do not enter
    When I manually: try to break in to an available house without the break-in item
    Then I should see an error notification
    And I confirm: I do not enter

  @kora_robberies @checklist @checklist:kora_robberies:store-rob-register @cat:crime
  Scenario: Rob a store register
    """
    Checklist test: Target a register ('Rob Register'): progress bar, skill check (qb-minigames if running), cash 50-200; needs min police (2 default).
    """
    When I manually: go to a store register and select the Rob Register target
    Then a progress bar should run
    And I confirm: a skill check appears (only applies when qb-minigames is running)
    And I confirm: I receive between $50 and $200 cash
    And I confirm: the robbery is refused when fewer than 2 police (the default minimum) are online

  @kora_robberies @checklist @checklist:kora_robberies:store-sticky-note @cat:crime
  Scenario: Sticky note with safe code
    """
    Checklist test: Registers can give a stickynote item (10% default) carrying the store's safe code.
    """
    When I manually: rob several store registers
    Then I confirm: some registers give a stickynote item (about 10% by default)
    And I should see a notification containing "There was a sticky note with a number on it."
    And I confirm: the sticky note carries the store's safe code

  @kora_robberies @checklist @checklist:kora_robberies:store-safe-code @cat:crime
  Scenario: Open store safe with code
    """
    Checklist test: Target safe > 'Enter Code', input number from sticky note; correct code opens it for 'Retrieve Loot'.
    """
    When I manually: target a store safe and select Enter Code
    Then a menu titled "Enter Safe Code" opens
    When I manually: enter the number from the sticky note
    Then I confirm: the correct code opens the safe
    When I manually: select Retrieve Loot on the opened safe
    Then I confirm: I receive the loot

  @kora_robberies @checklist @checklist:kora_robberies:store-safe-thermite @cat:crime
  Scenario: Blow up safe with thermite
    """
    Checklist test: Target safe > 'Blow Up Safe' (needs thermite item): thermite prop burns 5-10s, explosion, then 'Retrieve Loot' gives cash 500-1000.
    """
    Given I have 1 "thermite"
    When I manually: target a store safe and select Blow Up Safe
    Then I confirm: a thermite prop burns for 5 to 10 seconds and then the safe explodes
    When I manually: select Retrieve Loot on the safe
    Then I confirm: I receive between $500 and $1000 cash

  @kora_robberies @checklist @checklist:kora_robberies:store-reset @cat:crime @manual
  Scenario: Registers and safes refill after reset
    """
    Checklist test: After robbing, register/safe is unavailable for ~30 min and then becomes robbable again.
    """
    When I manually: rob a store register and a safe
    Then I confirm: the register and safe are unavailable right after
    When I manually: wait about 30 minutes for the reset time
    Then I confirm: the register and safe can be robbed again
