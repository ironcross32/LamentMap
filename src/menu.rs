#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum MenuError {
    #[error("a menu must contain at least one item")]
    EmptyMenu,
    #[error("a menu item must contain at least one spoken value")]
    EmptyValues,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MenuItem<P> {
    payload: P,
    values: Vec<String>,
    value_index: usize,
}

impl<P> MenuItem<P> {
    pub fn new<I, S>(payload: P, values: I) -> Result<Self, MenuError>
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        let values = values.into_iter().map(Into::into).collect::<Vec<_>>();
        if values.is_empty() {
            return Err(MenuError::EmptyValues);
        }
        Ok(Self {
            payload,
            values,
            value_index: 0,
        })
    }

    pub fn payload(&self) -> &P {
        &self.payload
    }

    pub fn selected_value(&self) -> &str {
        &self.values[self.value_index]
    }

    pub fn values(&self) -> &[String] {
        &self.values
    }

    fn cycle_value(&mut self, offset: isize) {
        self.value_index = wrapped_index(self.value_index, self.values.len(), offset);
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MenuCommand {
    Up,
    Down,
    Home,
    End,
    PageUp,
    PageDown,
    PreviousValue,
    NextValue,
    Confirm,
    Dismiss,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MenuEvent<P> {
    Announce(String),
    Confirmed { payload: P, value: String },
    Dismissed(String),
    Ignored,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Menu<P> {
    title: String,
    items: Vec<MenuItem<P>>,
    selected_index: usize,
    wraps: bool,
    confirmation_enabled: bool,
}

impl<P> Menu<P> {
    pub fn new(
        title: impl Into<String>,
        items: Vec<MenuItem<P>>,
        wraps: bool,
        confirmation_enabled: bool,
    ) -> Result<Self, MenuError> {
        if items.is_empty() {
            return Err(MenuError::EmptyMenu);
        }
        Ok(Self {
            title: title.into(),
            items,
            selected_index: 0,
            wraps,
            confirmation_enabled,
        })
    }

    pub fn opening_event(&self) -> MenuEvent<P> {
        MenuEvent::Announce(format!("{}. {}", self.title, self.current_message()))
    }

    pub fn selected_index(&self) -> usize {
        self.selected_index
    }

    pub fn selected_item(&self) -> &MenuItem<P> {
        &self.items[self.selected_index]
    }

    pub fn items(&self) -> &[MenuItem<P>] {
        &self.items
    }

    pub fn handle(&mut self, command: MenuCommand) -> MenuEvent<P>
    where
        P: Clone,
    {
        match command {
            MenuCommand::Up => self.move_selection(-1),
            MenuCommand::Down => self.move_selection(1),
            MenuCommand::Home => {
                self.selected_index = 0;
                self.announcement(None)
            }
            MenuCommand::End => {
                self.selected_index = self.items.len() - 1;
                self.announcement(None)
            }
            MenuCommand::PageUp => self.move_selection(-(self.page_size() as isize)),
            MenuCommand::PageDown => self.move_selection(self.page_size() as isize),
            MenuCommand::PreviousValue => {
                self.items[self.selected_index].cycle_value(-1);
                self.announcement(None)
            }
            MenuCommand::NextValue => {
                self.items[self.selected_index].cycle_value(1);
                self.announcement(None)
            }
            MenuCommand::Confirm if self.confirmation_enabled => {
                let item = self.selected_item();
                MenuEvent::Confirmed {
                    payload: item.payload.clone(),
                    value: item.selected_value().to_owned(),
                }
            }
            MenuCommand::Confirm => MenuEvent::Ignored,
            MenuCommand::Dismiss => MenuEvent::Dismissed("Menu closed.".into()),
        }
    }

    fn page_size(&self) -> usize {
        self.items.len().div_ceil(10).max(1)
    }

    fn move_selection(&mut self, offset: isize) -> MenuEvent<P> {
        if self.wraps {
            self.selected_index = wrapped_index(self.selected_index, self.items.len(), offset);
            return self.announcement(None);
        }

        if offset < 0 {
            let amount = offset.unsigned_abs();
            if amount > self.selected_index {
                self.selected_index = 0;
                self.announcement(Some("Top"))
            } else {
                self.selected_index -= amount;
                self.announcement(None)
            }
        } else {
            let amount = offset as usize;
            let last = self.items.len() - 1;
            if amount > last - self.selected_index {
                self.selected_index = last;
                self.announcement(Some("Bottom"))
            } else {
                self.selected_index += amount;
                self.announcement(None)
            }
        }
    }

    fn current_message(&self) -> &str {
        self.selected_item().selected_value()
    }

    fn announcement(&self, boundary: Option<&str>) -> MenuEvent<P> {
        MenuEvent::Announce(boundary.map_or_else(
            || self.current_message().to_owned(),
            |boundary| format!("{boundary}, {}", self.current_message()),
        ))
    }
}

fn wrapped_index(current: usize, len: usize, offset: isize) -> usize {
    let len = len as isize;
    (current as isize + offset).rem_euclid(len) as usize
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(payload: usize, value: &str) -> MenuItem<usize> {
        MenuItem::new(payload, [value]).unwrap()
    }

    fn menu(count: usize, wraps: bool, confirmation_enabled: bool) -> Menu<usize> {
        Menu::new(
            "Choices",
            (0..count)
                .map(|index| item(index, &format!("Item {}", index + 1)))
                .collect(),
            wraps,
            confirmation_enabled,
        )
        .unwrap()
    }

    #[test]
    fn opening_combines_the_title_and_first_item() {
        assert_eq!(
            menu(2, false, true).opening_event(),
            MenuEvent::Announce("Choices. Item 1".into())
        );
    }

    #[test]
    fn moves_normally_and_only_prefixes_attempted_nonwrapping_boundaries() {
        let mut menu = menu(3, false, true);
        assert_eq!(
            menu.handle(MenuCommand::Down),
            MenuEvent::Announce("Item 2".into())
        );
        assert_eq!(
            menu.handle(MenuCommand::Down),
            MenuEvent::Announce("Item 3".into())
        );
        assert_eq!(
            menu.handle(MenuCommand::Down),
            MenuEvent::Announce("Bottom, Item 3".into())
        );
        assert_eq!(menu.handle(MenuCommand::Up), MenuEvent::Announce("Item 2".into()));
        assert_eq!(menu.handle(MenuCommand::Up), MenuEvent::Announce("Item 1".into()));
        assert_eq!(
            menu.handle(MenuCommand::Up),
            MenuEvent::Announce("Top, Item 1".into())
        );
    }

    #[test]
    fn wraps_in_both_directions() {
        let mut menu = menu(3, true, true);
        assert_eq!(menu.handle(MenuCommand::Up), MenuEvent::Announce("Item 3".into()));
        assert_eq!(
            menu.handle(MenuCommand::Down),
            MenuEvent::Announce("Item 1".into())
        );
    }

    #[test]
    fn home_and_end_announce_endpoints_without_boundary_prefixes() {
        let mut menu = menu(3, false, true);
        assert_eq!(
            menu.handle(MenuCommand::End),
            MenuEvent::Announce("Item 3".into())
        );
        assert_eq!(
            menu.handle(MenuCommand::Home),
            MenuEvent::Announce("Item 1".into())
        );
    }

    #[test]
    fn paging_uses_ten_percent_rounded_up_and_wraps_modularly() {
        let mut menu = menu(21, true, true);
        assert_eq!(
            menu.handle(MenuCommand::PageDown),
            MenuEvent::Announce("Item 4".into())
        );
        assert_eq!(
            menu.handle(MenuCommand::PageUp),
            MenuEvent::Announce("Item 1".into())
        );
        assert_eq!(
            menu.handle(MenuCommand::PageUp),
            MenuEvent::Announce("Item 19".into())
        );
    }

    #[test]
    fn nonwrapping_page_overshoot_clamps_and_adds_the_boundary() {
        let mut menu = menu(21, false, true);
        assert_eq!(
            menu.handle(MenuCommand::PageUp),
            MenuEvent::Announce("Top, Item 1".into())
        );
        assert_eq!(
            menu.handle(MenuCommand::End),
            MenuEvent::Announce("Item 21".into())
        );
        assert_eq!(
            menu.handle(MenuCommand::PageDown),
            MenuEvent::Announce("Bottom, Item 21".into())
        );
    }

    #[test]
    fn adjustable_values_cycle_with_wraparound() {
        let adjustable = MenuItem::new(7, ["Low", "Medium", "High"]).unwrap();
        let mut menu = Menu::new("Level", vec![adjustable], false, true).unwrap();
        assert_eq!(
            menu.handle(MenuCommand::PreviousValue),
            MenuEvent::Announce("High".into())
        );
        assert_eq!(
            menu.handle(MenuCommand::NextValue),
            MenuEvent::Announce("Low".into())
        );
    }

    #[test]
    fn confirmation_is_optional_and_returns_payload_and_value() {
        let mut enabled = menu(2, false, true);
        enabled.handle(MenuCommand::Down);
        assert_eq!(
            enabled.handle(MenuCommand::Confirm),
            MenuEvent::Confirmed {
                payload: 1,
                value: "Item 2".into()
            }
        );
        assert_eq!(
            menu(1, false, false).handle(MenuCommand::Confirm),
            MenuEvent::Ignored
        );
    }

    #[test]
    fn escape_announces_dismissal() {
        assert_eq!(
            menu(1, false, true).handle(MenuCommand::Dismiss),
            MenuEvent::Dismissed("Menu closed.".into())
        );
    }

    #[test]
    fn single_item_menus_remain_stable_in_every_movement_mode() {
        for wraps in [false, true] {
            let mut menu = menu(1, wraps, true);
            for command in [
                MenuCommand::Home,
                MenuCommand::End,
                MenuCommand::PageDown,
                MenuCommand::PageUp,
            ] {
                let event = menu.handle(command);
                assert!(matches!(event, MenuEvent::Announce(_)));
                assert_eq!(menu.selected_index(), 0);
            }
        }
    }

    #[test]
    fn rejects_empty_menus_and_items_without_values() {
        assert_eq!(
            MenuItem::<usize>::new(1, Vec::<String>::new()),
            Err(MenuError::EmptyValues)
        );
        assert_eq!(
            Menu::<usize>::new("Empty", vec![], false, true),
            Err(MenuError::EmptyMenu)
        );
    }
}
